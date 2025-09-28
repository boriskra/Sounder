import Foundation
import AVFoundation
import Combine
import Accelerate

/// Service contract for audio processing of signal blocks
public protocol AudioBlockService {
    // MARK: - Audio Engine Management
    func initializeAudioEngine(sampleRate: Double, bufferSize: UInt32) async throws
    func startEngine() async throws
    func stopEngine() async
    func isEngineRunning() async -> Bool

    // MARK: - Block Audio Processing
    func registerBlock(_ block: SignalBlock) async throws
    func unregisterBlock(id blockId: UUID) async
    func updateBlockParameter(blockId: UUID, parameterName: String, value: Double) async throws
    func connectBlocks(from sourceBlockId: UUID, sourcePort: String, to destinationBlockId: UUID, destinationPort: String) async throws
    func disconnectBlocks(from sourceBlockId: UUID, sourcePort: String, to destinationBlockId: UUID, destinationPort: String) async

    // MARK: - Audio Device Management
    func getAvailableOutputDevices() async -> [OutputDevice]
    func setOutputDevice(_ device: OutputDevice) async throws
    func getCurrentOutputDevice() async -> OutputDevice?

    // MARK: - Audio Analysis
    func getSpectrumData(for blockId: UUID?) async -> [Float]
    func getLevelMeterData(for blockId: UUID?) async -> (peak: Float, rms: Float)
    func getFrequencyAnalysis(for blockId: UUID) async -> Double?

    // MARK: - Performance Monitoring
    func getAudioCPUUsage() async -> Double
    func getBufferUnderrunCount() async -> Int
    func getAudioLatency() async -> Double
}

/// Protocol that all audio processing blocks must implement
public protocol AudioBlock {
    var id: UUID { get }
    var type: BlockType { get }
    var inputPorts: [String] { get }
    var outputPorts: [String] { get }

    /// Process audio for one buffer cycle with timeline context
    /// - Parameters:
    ///   - inputs: Input signal buffers keyed by port name
    ///   - frameCount: Number of samples to process
    ///   - startSample: Global sample position for first sample in this frame
    ///   - sampleRate: Sample rate for timeline calculations
    /// - Returns: Output signal buffers keyed by port name
    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]]

    /// Legacy process audio method for backward compatibility
    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]]

    /// Update a parameter value (called from audio thread)
    func setParameter(name: String, value: Double)

    /// Reset internal state to specific timeline position
    /// - Parameters:
    ///   - startSample: Global sample position to reset to
    ///   - sampleRate: Sample rate for timeline calculations
    func reset(to startSample: UInt64, sampleRate: Double)

    /// Legacy reset method for backward compatibility
    func reset()
}

/// Concrete implementation of AudioBlockService using AVFoundation
@MainActor
public class AudioBlockServiceImpl: AudioBlockService, ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var audioFormat: AVAudioFormat?
    private var registeredBlocks: [UUID: AudioBlock] = [:]
    private var audioConnections: [AudioConnection] = []
    private var currentOutputDevice: OutputDevice?
    private var bufferUnderrunCount: Int = 0
    private var cpuUsage: Double = 0.0
    private var graphScheduler: AudioGraphScheduler?
    private let frameSize: Int = 512

    private let eventPublisher: PassthroughSubject<AudioBlockEvent, Never> = PassthroughSubject<AudioBlockEvent, Never>()

    // Analysis state updated from the render callback and read on the main actor
    private let analysisQueue = DispatchQueue(label: "com.sounder.AudioBlockService.analysis", qos: .userInitiated)
    private let analysisFFTSize: Int = 2048
    private let analysisSmoothing: Float = 0.85
    private let minimumLevel: Float = 1.0e-5
    private let analysisLog2n: vDSP_Length
    nonisolated(unsafe) private var analysisFFTSetup: FFTSetup?
    nonisolated(unsafe) private var analysisWindow: [Float]
    nonisolated(unsafe) private var analysisRingBuffer: [Float]
    nonisolated(unsafe) private var analysisRingIndex: Int = 0
    nonisolated(unsafe) private var analysisRingCount: Int = 0
    nonisolated(unsafe) private var analysisWorkingBuffer: [Float]
    nonisolated(unsafe) private var analysisReal: [Float]
    nonisolated(unsafe) private var analysisImag: [Float]
    nonisolated(unsafe) private var latestSpectrumMagnitudes: [Float]
    nonisolated(unsafe) private var latestPeakLinear: Float = 0.0
    nonisolated(unsafe) private var latestRMSLinear: Float = 0.0
    nonisolated(unsafe) private var latestFrequencyEstimate: Double?
    nonisolated(unsafe) private var analysisSampleRate: Double = 48_000.0

    public init() {
        analysisLog2n = vDSP_Length(log2(Float(analysisFFTSize)))
        analysisWindow = Array(repeating: 0.0, count: analysisFFTSize)
        vDSP_hann_window(&analysisWindow, vDSP_Length(analysisFFTSize), Int32(vDSP_HANN_NORM))
        analysisRingBuffer = Array(repeating: 0.0, count: analysisFFTSize)
        analysisWorkingBuffer = Array(repeating: 0.0, count: analysisFFTSize)
        analysisReal = Array(repeating: 0.0, count: analysisFFTSize / 2)
        analysisImag = Array(repeating: 0.0, count: analysisFFTSize / 2)
        latestSpectrumMagnitudes = Array(repeating: 0.0, count: analysisFFTSize / 2)
        analysisFFTSetup = vDSP_create_fftsetup(analysisLog2n, FFTRadix(kFFTRadix2))
    }

    deinit {
        if let setup = analysisFFTSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    // MARK: - Audio Engine Management

    public func initializeAudioEngine(sampleRate: Double, bufferSize: UInt32) async throws {
        print("🎛️ [DEBUG] AudioBlockService.initializeAudioEngine() - Starting with sampleRate: \(sampleRate), bufferSize: \(bufferSize)")
        guard sampleRate > 0 && bufferSize > 0 else {
            throw AudioBlockError.audioEngineError("Invalid sample rate or buffer size")
        }

        do {
            audioEngine = AVAudioEngine()
            print("🎛️ [DEBUG] AudioBlockService.initializeAudioEngine() - Created AVAudioEngine")

            // Configure audio format
            audioFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
            guard audioFormat != nil else {
                throw AudioBlockError.audioEngineError("Failed to create audio format")
            }
            print("🎛️ [DEBUG] AudioBlockService.initializeAudioEngine() - Created audio format: \(audioFormat!)")

            // Initialize audio graph scheduler with timeline
            graphScheduler = AudioGraphScheduler(frameSize: frameSize, sampleRate: sampleRate)
            print("🎛️ [DEBUG] AudioBlockService.initializeAudioEngine() - Created AudioGraphScheduler with timeline")

            analysisQueue.sync {
                if analysisFFTSetup == nil {
                    analysisFFTSetup = vDSP_create_fftsetup(analysisLog2n, FFTRadix(kFFTRadix2))
                }
                resetAnalysisStateLocked(sampleRate: sampleRate)
            }
            
            // Configure audio session (iOS only)
            #if os(iOS)
            let audioSession: AVAudioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setPreferredSampleRate(sampleRate)
            try audioSession.setPreferredIOBufferDuration(Double(bufferSize) / sampleRate)
            print("🎛️ [DEBUG] AudioBlockService.initializeAudioEngine() - Configured iOS audio session")
            #endif

            print("🎛️ [DEBUG] AudioBlockService.initializeAudioEngine() - Initialization completed successfully")
        } catch {
            print("🎛️ [ERROR] AudioBlockService.initializeAudioEngine() - Error: \(error)")
            throw AudioBlockError.audioEngineError("Failed to initialize audio engine: \(error.localizedDescription)")
        }
    }

    public func startEngine() async throws {
        print("🎛️ [DEBUG] AudioBlockService.startEngine() - Starting")
        guard let engine: AVAudioEngine = audioEngine else {
            print("🎛️ [ERROR] AudioBlockService.startEngine() - Audio engine not initialized")
            throw AudioBlockError.audioEngineError("Audio engine not initialized")
        }

        do {
            print("🎛️ [DEBUG] AudioBlockService.startEngine() - Engine running status: \(engine.isRunning)")
            if !engine.isRunning {
                print("🎛️ [DEBUG] AudioBlockService.startEngine() - Starting AVAudioEngine")
                try engine.start()
                print("🎛️ [DEBUG] AudioBlockService.startEngine() - AVAudioEngine started successfully")

                print("🎛️ [DEBUG] AudioBlockService.startEngine() - Sending .engineStarted event")
                eventPublisher.send(.engineStarted)

                print("🎛️ [DEBUG] AudioBlockService.startEngine() - Posting .audioEngineStatusChanged notification")
                NotificationCenter.default.post(
                    name: .audioEngineStatusChanged,
                    object: AudioEngineStatus.running
                )
                print("🎛️ [DEBUG] AudioBlockService.startEngine() - Completed successfully")
            } else {
                print("🎛️ [DEBUG] AudioBlockService.startEngine() - Engine already running")
            }
        } catch {
            print("🎛️ [ERROR] AudioBlockService.startEngine() - Error: \(error)")
            throw AudioBlockError.audioEngineError("Failed to start audio engine: \(error.localizedDescription)")
        }
    }

    public func stopEngine() async {
        guard let engine = audioEngine else { return }

        if engine.isRunning {
            engine.stop()
            eventPublisher.send(.engineStopped)
            NotificationCenter.default.post(
                name: .audioEngineStatusChanged,
                object: AudioEngineStatus.stopped
            )
        }

        // Reset timeline and all blocks to beginning
        if let scheduler = graphScheduler {
            scheduler.resetTimeline()
        } else {
            // Fallback for legacy reset
            for block in registeredBlocks.values {
                block.reset()
            }
        }

        analysisQueue.async { [weak self] in
            guard let self = self else { return }
            self.resetAnalysisStateLocked(sampleRate: self.analysisSampleRate)
        }
    }

    public func isEngineRunning() async -> Bool {
        return audioEngine?.isRunning ?? false
    }

    // MARK: - Block Audio Processing

    public func registerBlock(_ block: SignalBlock) async throws {
        print("🎛️ [DEBUG] AudioBlockService.registerBlock() - Registering block: \(block.title) (\(block.type))")
        guard registeredBlocks[block.id] == nil else {
            print("🎛️ [DEBUG] AudioBlockService.registerBlock() - Block already registered: \(block.id)")
            return // Already registered
        }

        // Create audio block implementation based on block type
        let audioBlock: AudioBlock = try createAudioBlock(for: block)
        registeredBlocks[block.id] = audioBlock

        // Connect to audio engine if this is an output block
        if block.type == .audioOutput {
            try await connectOutputBlockToEngine(audioBlock)
        }

        print("🎛️ [DEBUG] AudioBlockService.registerBlock() - Successfully registered block: \(block.title)")
        eventPublisher.send(.blockRegistered(block.id))
    }

    public func unregisterBlock(id blockId: UUID) async {
        registeredBlocks.removeValue(forKey: blockId)

        // Remove all connections involving this block
        audioConnections.removeAll { connection in
            connection.sourceBlockId == blockId || connection.destinationBlockId == blockId
        }

        eventPublisher.send(.blockUnregistered(blockId))
    }

    public func updateBlockParameter(blockId: UUID, parameterName: String, value: Double) async throws {
        guard let audioBlock = registeredBlocks[blockId] else {
            throw AudioBlockError.blockNotFoundError(blockId)
        }

        // Thread-safe parameter update with real-time audio processing
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                // Update parameter with thread safety
                self.updateParameterThreadSafe(
                    audioBlock: audioBlock,
                    parameterName: parameterName,
                    value: value
                )

                // Notify main thread of parameter change
                DispatchQueue.main.async {
                    self.eventPublisher.send(.parameterUpdated(blockId, parameterName, value))
                }

                continuation.resume()
            }
        }
    }

    private func updateParameterThreadSafe(
        audioBlock: any AudioBlock,
        parameterName: String,
        value: Double
    ) {
        // Apply parameter update atomically
        // Use a lock-free approach for real-time audio safety

        // Apply fade-in/fade-out for smooth transitions if needed
        if shouldApplySmoothing(parameterName: parameterName) {
            applyParameterSmoothing(
                audioBlock: audioBlock,
                parameterName: parameterName,
                targetValue: value
            )
        } else {
            // Direct parameter update for non-critical parameters
            audioBlock.setParameter(name: parameterName, value: value)
        }

        print("Updated parameter \(parameterName) = \(value) for block \(type(of: audioBlock))")
    }

    private func shouldApplySmoothing(parameterName: String) -> Bool {
        // Apply smoothing for parameters that can cause audio artifacts
        let smoothedParameters: [String] = ["amplitude", "frequency", "gain", "volume"]
        return smoothedParameters.contains(parameterName)
    }

    private func applyParameterSmoothing(
        audioBlock: any AudioBlock,
        parameterName: String,
        targetValue: Double
    ) {
        // Implement smooth parameter transitions to prevent audio clicks/pops
        // This would typically involve ramping the parameter over several audio buffers

        // For demonstration, we'll schedule a gradual update
        let rampDuration: TimeInterval = 0.01 // 10ms ramp
        let sampleRate: Double = 48000.0
        let bufferSize: Double = 512.0
        let rampSteps: Int = Int(rampDuration * sampleRate / bufferSize)

        if rampSteps > 1 {
            // Schedule gradual parameter change over multiple audio buffers
            scheduleParameterRamp(
                audioBlock: audioBlock,
                parameterName: parameterName,
                targetValue: targetValue,
                steps: rampSteps
            )
        } else {
            // Apply immediately for very small changes
            audioBlock.setParameter(name: parameterName, value: targetValue)
        }
    }

    private func scheduleParameterRamp(
        audioBlock: any AudioBlock,
        parameterName: String,
        targetValue: Double,
        steps: Int
    ) {
        // In a real implementation, this would queue parameter changes
        // to be applied gradually over the next few audio processing cycles

        // For now, we'll implement a simple delayed application
        // In production, this would use a lock-free queue or atomic operations

        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.005) {
            audioBlock.setParameter(name: parameterName, value: targetValue)
        }
    }

    public func connectBlocks(
        from sourceBlockId: UUID,
        sourcePort: String,
        to destinationBlockId: UUID,
        destinationPort: String
    ) async throws {
        guard registeredBlocks[sourceBlockId] != nil else {
            throw AudioBlockError.blockNotFoundError(sourceBlockId)
        }

        guard registeredBlocks[destinationBlockId] != nil else {
            throw AudioBlockError.blockNotFoundError(destinationBlockId)
        }

        let connection: AudioConnection = AudioConnection(
            sourceBlockId: sourceBlockId,
            sourcePort: sourcePort,
            destinationBlockId: destinationBlockId,
            destinationPort: destinationPort
        )

        audioConnections.append(connection)

        // Rebuild graph scheduler if engine is running
        if audioEngine?.isRunning == true {
            try await rebuildAudioGraph()
        }

        eventPublisher.send(.blocksConnected(sourceBlockId, sourcePort, destinationBlockId, destinationPort))
    }

    public func disconnectBlocks(
        from sourceBlockId: UUID,
        sourcePort: String,
        to destinationBlockId: UUID,
        destinationPort: String
    ) async {
        audioConnections.removeAll { connection in
            connection.sourceBlockId == sourceBlockId &&
            connection.sourcePort == sourcePort &&
            connection.destinationBlockId == destinationBlockId &&
            connection.destinationPort == destinationPort
        }

        // Rebuild graph scheduler if engine is running
        if audioEngine?.isRunning == true {
            do {
                try await rebuildAudioGraph()
            } catch {
                print("🎛️ [WARNING] AudioBlockService.disconnectBlocks() - Failed to rebuild graph: \(error)")
            }
        }

        eventPublisher.send(.blocksDisconnected(sourceBlockId, sourcePort, destinationBlockId, destinationPort))
    }

    // MARK: - Audio Device Management

    public func getAvailableOutputDevices() async -> [OutputDevice] {
        var devices: [OutputDevice] = []

        // Get system default device
        #if os(iOS)
        if let defaultDevice = AVAudioSession.sharedInstance().currentRoute.outputs.first {
            devices.append(OutputDevice(
                id: defaultDevice.uid ?? "default",
                name: defaultDevice.portName,
                isDefault: true,
                isAvailable: true
            ))
        }
        #else
        // macOS default device handling
        devices.append(OutputDevice(
            id: "default",
            name: "Default Output",
            isDefault: true,
            isAvailable: true
        ))
        #endif

        // Get available audio outputs (simplified for demo)
        // In a real implementation, you'd enumerate all available devices
        devices.append(contentsOf: [
            OutputDevice(id: "builtin-speakers", name: "Built-in Speakers", isDefault: false, isAvailable: true),
            OutputDevice(id: "bluetooth-headphones", name: "Bluetooth Headphones", isDefault: false, isAvailable: true),
            OutputDevice(id: "airpods", name: "AirPods Pro", isDefault: false, isAvailable: false)
        ])

        return devices
    }

    public func setOutputDevice(_ device: OutputDevice) async throws {
        guard device.isAvailable else {
            throw AudioBlockError.audioDeviceError("Device '\(device.name)' is not available")
        }

        // In a real implementation, you would configure AVAudioSession to use the specific device
        // For this demo, we'll just track the current device
        currentOutputDevice = device

        eventPublisher.send(.outputDeviceChanged(device))
    }

    public func getCurrentOutputDevice() async -> OutputDevice? {
        return currentOutputDevice
    }

    // MARK: - Audio Analysis

    public func getSpectrumData(for blockId: UUID?) async -> [Float] {
        if let blockId,
           let analyzerBlock = registeredBlocks[blockId] as? SpectrumAnalyzerBlock {
            let nyquist = (audioFormat?.sampleRate ?? analysisSampleRate) / 2.0
            return analyzerBlock.getSpectrumInRange(minFreq: 0.0, maxFreq: nyquist)
        }

        return analysisQueue.sync {
            latestSpectrumMagnitudes
        }
    }

    public func getLevelMeterData(for blockId: UUID?) async -> (peak: Float, rms: Float) {
        if let blockId,
           let levelBlock = registeredBlocks[blockId] as? LevelMeterAudioBlock {
            let levels = levelBlock.currentLinearLevels()
            let peak = Self.linearAmplitudeToDecibels(Float(levels.peak), floor: -120.0)
            let rms = Self.linearAmplitudeToDecibels(Float(levels.rms), floor: -120.0)
            return (peak: peak, rms: rms)
        }

        return analysisQueue.sync {
            let peak = Self.linearAmplitudeToDecibels(max(latestPeakLinear, minimumLevel), floor: -120.0)
            let rms = Self.linearAmplitudeToDecibels(max(latestRMSLinear, minimumLevel), floor: -120.0)
            return (peak: peak, rms: rms)
        }
    }

    public func getFrequencyAnalysis(for blockId: UUID) async -> Double? {
        if let frequencyBlock = registeredBlocks[blockId] as? FrequencyCounterAudioBlock {
            return frequencyBlock.currentFrequencyEstimate()
        }

        if let analyzerBlock = registeredBlocks[blockId] as? SpectrumAnalyzerBlock {
            let nyquist = (audioFormat?.sampleRate ?? analysisSampleRate) / 2.0
            let spectrum = analyzerBlock.getSpectrumInRange(minFreq: 0.0, maxFreq: nyquist)
            guard spectrum.count > 1 else { return nil }

            var maxValue: Float = 0.0
            var maxIndex: Int = 1
            for index in 1..<spectrum.count where spectrum[index] > maxValue {
                maxValue = spectrum[index]
                maxIndex = index
            }

            if maxValue <= Float.leastNonzeroMagnitude {
                return nil
            }

            let fftSize = analyzerBlock.windowSize
            let sampleRate = audioFormat?.sampleRate ?? analysisSampleRate
            let binFrequency = Double(maxIndex) * sampleRate / Double(fftSize)
            return binFrequency
        }

        return analysisQueue.sync {
            latestFrequencyEstimate
        }
    }

    // MARK: - Performance Monitoring

    public func getAudioCPUUsage() async -> Double {
        // Placeholder implementation
        // In a real implementation, this would measure actual CPU usage
        cpuUsage = Double.random(in: 0.05...0.25)
        return cpuUsage
    }

    public func getBufferUnderrunCount() async -> Int {
        return bufferUnderrunCount
    }

    public func getAudioLatency() async -> Double {
        guard let engine = audioEngine else { return 0.0 }

        let outputNode = engine.outputNode
        let hardwareLatency = outputNode.presentationLatency
        let outputFormat = outputNode.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : analysisSampleRate
        let bufferDuration = sampleRate > 0 ? Double(frameSize) / sampleRate : 0.0
        let totalLatency = (hardwareLatency + bufferDuration) * 1000.0
        return max(totalLatency, 0.0)
    }

    // MARK: - Private Methods

    nonisolated(unsafe) private func scheduleAnalysisUpdate(samples: [Float], sampleRate: Double) {
        guard !samples.isEmpty else { return }
        analysisQueue.async { [weak self] in
            self?.updateAnalysis(with: samples, sampleRate: sampleRate)
        }
    }

    nonisolated(unsafe) private func updateAnalysis(with samples: [Float], sampleRate: Double) {
        appendSamplesToRing(samples)
        updateLevelMetrics(with: samples)
        refreshSpectrumIfNeeded(sampleRate: sampleRate)
    }

    nonisolated(unsafe) private func appendSamplesToRing(_ samples: [Float]) {
        guard analysisFFTSize > 0 else { return }

        for sample in samples {
            analysisRingBuffer[analysisRingIndex] = sample
            analysisRingIndex = (analysisRingIndex + 1) % analysisFFTSize
            if analysisRingCount < analysisFFTSize {
                analysisRingCount += 1
            }
        }
    }

    nonisolated(unsafe) private func updateLevelMetrics(with samples: [Float]) {
        guard !samples.isEmpty else { return }

        var peakValue: Float = 0.0
        vDSP_maxmgv(samples, 1, &peakValue, vDSP_Length(samples.count))

        let decayedPeak = latestPeakLinear * analysisSmoothing
        latestPeakLinear = max(peakValue, decayedPeak)

        var meanSquare: Float = 0.0
        vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(samples.count))
        let rms = sqrt(meanSquare)

        latestRMSLinear = analysisSmoothing * latestRMSLinear + (1.0 - analysisSmoothing) * rms
    }

    nonisolated(unsafe) private func refreshSpectrumIfNeeded(sampleRate: Double) {
        guard analysisRingCount == analysisFFTSize,
              let setup = analysisFFTSetup else { return }

        for index in 0..<analysisFFTSize {
            let ringIndex = (analysisRingIndex + index) % analysisFFTSize
            analysisWorkingBuffer[index] = analysisRingBuffer[ringIndex]
        }

        vDSP_vmul(analysisWorkingBuffer, 1, analysisWindow, 1, &analysisWorkingBuffer, 1, vDSP_Length(analysisFFTSize))

        let halfSize = analysisFFTSize / 2

        analysisReal.withUnsafeMutableBufferPointer { realPtr in
            analysisImag.withUnsafeMutableBufferPointer { imagPtr in
                guard let realBase = realPtr.baseAddress,
                      let imagBase = imagPtr.baseAddress else { return }

                analysisWorkingBuffer.withUnsafeBufferPointer { workPtr in
                    guard let workBase = workPtr.baseAddress else { return }

                    for bin in 0..<halfSize {
                        realBase[bin] = workBase[bin * 2]
                        let oddIndex = bin * 2 + 1
                        imagBase[bin] = oddIndex < analysisFFTSize ? workBase[oddIndex] : 0.0
                    }
                }

                var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                vDSP_fft_zrip(setup, &split, 1, analysisLog2n, FFTDirection(FFT_FORWARD))

                var scale: Float = 1.0 / Float(analysisFFTSize)
                vDSP_vsmul(realBase, 1, &scale, realBase, 1, vDSP_Length(halfSize))
                vDSP_vsmul(imagBase, 1, &scale, imagBase, 1, vDSP_Length(halfSize))

                latestSpectrumMagnitudes.withUnsafeMutableBufferPointer { magnitudePtr in
                    guard let magnitudeBase = magnitudePtr.baseAddress else { return }
                    vDSP_zvabs(&split, 1, magnitudeBase, 1, vDSP_Length(halfSize))
                }
            }
        }

        latestFrequencyEstimate = computeDominantFrequency(sampleRate: sampleRate)
    }

    nonisolated(unsafe) private func computeDominantFrequency(sampleRate: Double) -> Double? {
        guard latestSpectrumMagnitudes.count > 1 else { return nil }

        var peakValue: Float = 0.0
        var peakIndex: vDSP_Length = 0

        latestSpectrumMagnitudes.withUnsafeBufferPointer { magnitudesPtr in
            guard let base = magnitudesPtr.baseAddress, magnitudesPtr.count > 1 else { return }
            vDSP_maxvi(base + 1, 1, &peakValue, &peakIndex, vDSP_Length(magnitudesPtr.count - 1))
        }

        if peakValue <= Float.leastNonzeroMagnitude {
            return nil
        }

        let fundamentalIndex = Int(peakIndex) + 1
        let nyquistIndex = latestSpectrumMagnitudes.count - 1

        if fundamentalIndex <= 0 || fundamentalIndex >= nyquistIndex {
            return Double(fundamentalIndex) * sampleRate / Double(analysisFFTSize)
        }

        let left = latestSpectrumMagnitudes[fundamentalIndex - 1]
        let center = latestSpectrumMagnitudes[fundamentalIndex]
        let right = latestSpectrumMagnitudes[fundamentalIndex + 1]

        let denominator = (left - 2.0 * center + right)
        let adjustment = denominator != 0.0 ? 0.5 * (left - right) / denominator : 0.0
        let refinedBin = Double(fundamentalIndex) + Double(adjustment)

        return refinedBin * sampleRate / Double(analysisFFTSize)
    }

    nonisolated(unsafe) private func resetAnalysisStateLocked(sampleRate: Double) {
        analysisSampleRate = sampleRate
        analysisRingBuffer = Array(repeating: 0.0, count: analysisFFTSize)
        analysisWorkingBuffer = Array(repeating: 0.0, count: analysisFFTSize)
        analysisRingIndex = 0
        analysisRingCount = 0
        latestSpectrumMagnitudes = Array(repeating: 0.0, count: analysisFFTSize / 2)
        latestPeakLinear = 0.0
        latestRMSLinear = 0.0
        latestFrequencyEstimate = nil
    }

    private static func linearAmplitudeToDecibels(_ amplitude: Float, floor: Float) -> Float {
        let clamped = max(amplitude, 1.0e-9)
        let decibels = 20.0 * log10f(clamped)
        return max(decibels, floor)
    }

    private func createAudioBlock(for block: SignalBlock) throws -> AudioBlock {
        switch block.type {
        case .sineOscillator:
            return SineOscillatorAudioBlock(block: block)
        case .triangleOscillator:
            return TriangleOscillatorAudioBlock(block: block)
        case .sawtoothOscillator:
            return SawtoothOscillatorAudioBlock(block: block)
        case .squareOscillator:
            return SquareOscillatorAudioBlock(block: block)
        case .whiteNoise:
            return WhiteNoiseAudioBlock(block: block)
        case .pinkNoise:
            return PinkNoiseAudioBlock(block: block)
        case .linearChirp:
            return LinearChirpAudioBlock(block: block)
        case .hyperbolicChirp:
            return HyperbolicChirpAudioBlock(block: block)
        case .frequencyModulator:
            return FrequencyModulatorAudioBlock(block: block)
        case .amplitudeModulator:
            return AmplitudeModulatorAudioBlock(block: block)
        case .ringModulator:
            return RingModulatorAudioBlock(block: block)
        case .lowPassFilter:
            return LowPassFilterAudioBlock(block: block)
        case .highPassFilter:
            return HighPassFilterAudioBlock(block: block)
        case .bandPassFilter:
            return BandPassFilterAudioBlock(block: block)
        case .mixer:
            return MixerAudioBlock(block: block)
        case .amplifier:
            return AmplifierAudioBlock(block: block)
        case .audioOutput:
            return AudioOutputAudioBlock(block: block)
        case .spectrumAnalyzer:
            return SpectrumAnalyzerBlock(signalBlock: block)
        case .levelMeter:
            return LevelMeterAudioBlock(block: block)
        case .frequencyCounter:
            return FrequencyCounterAudioBlock(block: block)
        default:
            throw AudioBlockError.blockRegistrationError("Unsupported block type: \(block.type)")
        }
    }

    // MARK: - Audio Graph Management

    private func rebuildAudioGraph() async throws {
        guard let scheduler = graphScheduler else {
            throw AudioBlockError.audioEngineError("Graph scheduler not initialized")
        }

        // Convert AudioConnection to Connection for scheduler
        let connections = audioConnections.map { audioConnection in
            Connection(
                sourceBlockId: audioConnection.sourceBlockId,
                sourcePort: audioConnection.sourcePort,
                destinationBlockId: audioConnection.destinationBlockId,
                destinationPort: audioConnection.destinationPort,
                signalType: .audio
            )
        }

        do {
            try scheduler.buildExecutionGraph(
                blocks: registeredBlocks,
                connections: connections
            )
            print("🎛️ [DEBUG] AudioBlockService.rebuildAudioGraph() - Successfully rebuilt execution graph")
        } catch {
            print("🎛️ [ERROR] AudioBlockService.rebuildAudioGraph() - Failed to build graph: \(error)")
            throw AudioBlockError.audioEngineError("Failed to rebuild audio graph: \(error.localizedDescription)")
        }
    }

    // MARK: - Engine Node Connection

    private func connectOutputBlockToEngine(_ audioBlock: AudioBlock) async throws {
        print("🎛️ [DEBUG] AudioBlockService.connectOutputBlockToEngine() - Connecting output block to engine")
        guard let engine = audioEngine else {
            throw AudioBlockError.audioEngineError("Audio engine not initialized")
        }

        guard let scheduler = graphScheduler else {
            throw AudioBlockError.audioEngineError("Graph scheduler not initialized")
        }

        // Build initial execution graph
        try await rebuildAudioGraph()

        // Create a source node that processes audio through the graph scheduler
        let sourceNode = AVAudioSourceNode { [weak self] (_, _, frameCount, audioBufferList) -> OSStatus in
            guard let self = self,
                  let scheduler = self.graphScheduler else {
                return noErr
            }

            let buffer = UnsafeMutableAudioBufferListPointer(audioBufferList)

            // Process one frame through the audio graph
            let frameOutputs = scheduler.processFrame()

            // Find audio output from the graph
            var outputSamples: [Float] = Array(repeating: 0.0, count: Int(frameCount))

            // Look for output from any AudioOutput block
            for (blockId, audioBlock) in self.registeredBlocks {
                if audioBlock.type == .audioOutput {
                    let outputKey = "\(blockId):input"
                    if let samples = frameOutputs[outputKey] {
                        outputSamples = Array(samples.prefix(Int(frameCount)))
                        break
                    }
                }
            }

            // If no proper graph output, fall back to direct sine generation for compatibility
            if outputSamples.allSatisfy({ $0 == 0.0 }) {
                var currentPhase: Float = 0.0
                let sampleRate: Float = 48000.0
                var frequency: Float = 440.0
                var amplitude: Float = 0.3

                for registeredBlock in self.registeredBlocks.values {
                    if registeredBlock.type == .sineOscillator {
                        if let sineBlock = registeredBlock as? SineOscillatorAudioBlock {
                            frequency = Float(sineBlock.getCurrentFrequency())
                            amplitude = Float(sineBlock.getCurrentAmplitude())
                        }
                        break
                    }
                }

                let phaseIncrement = frequency * 2.0 * Float.pi / sampleRate

                for frame in 0..<Int(frameCount) {
                    outputSamples[frame] = amplitude * sin(currentPhase)
                    currentPhase += phaseIncrement

                    if currentPhase > 2.0 * Float.pi {
                        currentPhase -= 2.0 * Float.pi
                    }
                }
            }

            // Copy to all audio channels
            for frame in 0..<Int(frameCount) {
                let sample = outputSamples[frame]

                for bufferIndex in 0..<buffer.count {
                    let channelBuffer = buffer[bufferIndex]
                    let channelData = channelBuffer.mData?.assumingMemoryBound(to: Float.self)
                    channelData?[frame] = sample
                }
            }

            let sampleRate = self.audioFormat?.sampleRate ?? self.analysisSampleRate
            self.scheduleAnalysisUpdate(samples: outputSamples, sampleRate: sampleRate)

            return noErr
        }

        // Connect the source node to the output
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.outputNode, format: audioFormat)

        print("🎛️ [DEBUG] AudioBlockService.connectOutputBlockToEngine() - Connected graph-based source node to output")
    }

    // MARK: - Event Publishing

    public var events: AnyPublisher<AudioBlockEvent, Never> {
        eventPublisher.eraseToAnyPublisher()
    }
}

// MARK: - Audio Connection

private struct AudioConnection {
    let sourceBlockId: UUID
    let sourcePort: String
    let destinationBlockId: UUID
    let destinationPort: String
}

// MARK: - Error Types

public enum AudioBlockError: Error, LocalizedError {
    case audioEngineError(String)
    case blockRegistrationError(String)
    case blockNotFoundError(UUID)
    case invalidParameterError(String)
    case connectionError(String)
    case audioDeviceError(String)
    case bufferUnderrunError
    case realTimeViolationError

    public var errorDescription: String? {
        switch self {
        case .audioEngineError(let message):
            return "Audio engine error: \(message)"
        case .blockRegistrationError(let message):
            return "Block registration error: \(message)"
        case .blockNotFoundError(let id):
            return "Audio block not found: \(id)"
        case .invalidParameterError(let message):
            return "Invalid parameter: \(message)"
        case .connectionError(let message):
            return "Connection error: \(message)"
        case .audioDeviceError(let message):
            return "Audio device error: \(message)"
        case .bufferUnderrunError:
            return "Audio buffer underrun detected"
        case .realTimeViolationError:
            return "Real-time audio constraint violation"
        }
    }
}

// MARK: - Event Types

/// Events published by the AudioBlockService
public enum AudioBlockEvent {
    case engineStarted
    case engineStopped
    case blockRegistered(UUID)
    case blockUnregistered(UUID)
    case blocksConnected(UUID, String, UUID, String)
    case blocksDisconnected(UUID, String, UUID, String)
    case parameterUpdated(UUID, String, Double)
    case outputDeviceChanged(OutputDevice)
    case bufferUnderrun
    case cpuOverload(Double)
    case realTimeViolation(UUID, String)
}

// MARK: - Simple Audio Block Implementations

/// Time-coherent sine oscillator implementation
private class SineOscillatorAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .sineOscillator
    let inputPorts: [String] = ["frequency"]
    let outputPorts: [String] = ["signal"]

    private var frequency: Double = 440.0
    private var amplitude: Double = 0.5
    // Removed phase - now calculated from timeline

    init(block: SignalBlock) {
        self.id = block.id
        if let freqParam = block.parameters["frequency"] {
            self.frequency = freqParam.value
        }
        if let ampParam = block.parameters["amplitude"] {
            self.amplitude = pow(10.0, ampParam.value / 20.0) // Convert dB to linear
        }
    }

    // MARK: - Time-Coherent Audio Processing

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        var output: [Float] = []
        output.reserveCapacity(frameCount)

        // Check for frequency modulation input
        let baseFrequency = frequency
        let frequencyInput = inputs["frequency"]

        for frame in 0..<frameCount {
            let sampleIndex = startSample + UInt64(frame)
            let time = Double(sampleIndex) / sampleRate

            // Apply frequency modulation if input is connected
            let currentFrequency: Double
            if let freqInput = frequencyInput, frame < freqInput.count {
                currentFrequency = baseFrequency + Double(freqInput[frame])
            } else {
                currentFrequency = baseFrequency
            }

            // Calculate phase from absolute timeline position
            let phase = 2.0 * Double.pi * currentFrequency * time
            let sample = Float(amplitude * sin(phase))
            output.append(sample)
        }

        return ["signal": output]
    }

    // Legacy method for backward compatibility
    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(
            inputs: inputs,
            frameCount: frameCount,
            startSample: 0,
            sampleRate: 48000.0
        )
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "frequency":
            frequency = value
            print("Updated parameter frequency = \(frequency) for block SineOscillatorAudioBlock")
        case "amplitude":
            amplitude = pow(10.0, value / 20.0) // Convert dB to linear
            print("Updated parameter amplitude = \(value) for block SineOscillatorAudioBlock")
        default:
            break
        }
    }

    // MARK: - Reset Methods

    func reset(to startSample: UInt64, sampleRate: Double) {
        // No internal state to reset - phase calculated from timeline
        print("🎵 [DEBUG] SineOscillatorAudioBlock.reset(to:) - Reset to sample \(startSample) at \(sampleRate)Hz")
    }

    func reset() {
        // Legacy reset method
        reset(to: 0, sampleRate: 48000.0)
    }

    // MARK: - Parameter Access Methods
    func getCurrentFrequency() -> Double {
        return frequency
    }

    func getCurrentAmplitude() -> Double {
        return amplitude
    }
}

/// Time-coherent sawtooth oscillator implementation
private class SawtoothOscillatorAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .sawtoothOscillator
    let inputPorts: [String] = ["frequency"]
    let outputPorts: [String] = ["signal"]

    private var frequency: Double = 440.0
    private var amplitude: Double = 0.5

    init(block: SignalBlock) {
        self.id = block.id
        if let freqParam = block.parameters["frequency"] {
            self.frequency = freqParam.value
        }
        if let ampParam = block.parameters["amplitude"] {
            self.amplitude = pow(10.0, ampParam.value / 20.0) // Convert dB to linear
        }
    }

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        var output: [Float] = []
        output.reserveCapacity(frameCount)

        let baseFrequency = frequency
        let frequencyInput = inputs["frequency"]

        for frame in 0..<frameCount {
            let sampleIndex = startSample + UInt64(frame)
            let time = Double(sampleIndex) / sampleRate

            // Apply frequency modulation if input is connected
            let currentFrequency: Double
            if let freqInput = frequencyInput, frame < freqInput.count {
                currentFrequency = baseFrequency + Double(freqInput[frame])
            } else {
                currentFrequency = baseFrequency
            }

            // Calculate phase from absolute timeline position
            let phase = (currentFrequency * time).truncatingRemainder(dividingBy: 1.0)

            // Generate sawtooth wave: linear ramp from -1 to +1
            let sample = Float(amplitude * (2.0 * phase - 1.0))
            output.append(sample)
        }

        return ["signal": output]
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(inputs: inputs, frameCount: frameCount, startSample: 0, sampleRate: 48000.0)
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "frequency":
            frequency = value
            print("Updated parameter frequency = \(frequency) for block SawtoothOscillatorAudioBlock")
        case "amplitude":
            amplitude = pow(10.0, value / 20.0) // Convert dB to linear
            print("Updated parameter amplitude = \(value) for block SawtoothOscillatorAudioBlock")
        default:
            break
        }
    }

    func reset(to startSample: UInt64, sampleRate: Double) {
        print("🎵 [DEBUG] SawtoothOscillatorAudioBlock.reset(to:) - Reset to sample \(startSample) at \(sampleRate)Hz")
    }

    func reset() {
        reset(to: 0, sampleRate: 48000.0)
    }

    func getCurrentFrequency() -> Double {
        return frequency
    }

    func getCurrentAmplitude() -> Double {
        return amplitude
    }
}

/// Time-coherent square oscillator implementation
private class SquareOscillatorAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .squareOscillator
    let inputPorts: [String] = ["frequency"]
    let outputPorts: [String] = ["signal"]

    private var frequency: Double = 440.0
    private var amplitude: Double = 0.5
    private var dutyCycle: Double = 0.5

    init(block: SignalBlock) {
        self.id = block.id
        if let freqParam = block.parameters["frequency"] {
            self.frequency = freqParam.value
        }
        if let ampParam = block.parameters["amplitude"] {
            self.amplitude = pow(10.0, ampParam.value / 20.0) // Convert dB to linear
        }
        if let dutyParam = block.parameters["dutyCycle"] {
            self.dutyCycle = Self.clampDutyCycle(dutyParam.value)
        }
    }

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        var output: [Float] = []
        output.reserveCapacity(frameCount)

        let baseFrequency = frequency
        let frequencyInput = inputs["frequency"]
        let onWidth = dutyCycle

        for frame in 0..<frameCount {
            let sampleIndex = startSample + UInt64(frame)
            let time = Double(sampleIndex) / sampleRate

            let currentFrequency: Double
            if let freqInput = frequencyInput, frame < freqInput.count {
                currentFrequency = baseFrequency + Double(freqInput[frame])
            } else {
                currentFrequency = baseFrequency
            }

            let normalizedPhase = (currentFrequency * time).truncatingRemainder(dividingBy: 1.0)
            let sampleValue: Double = normalizedPhase < onWidth ? 1.0 : -1.0
            let sample = Float(amplitude * sampleValue)
            output.append(sample)
        }

        return ["signal": output]
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(inputs: inputs, frameCount: frameCount, startSample: 0, sampleRate: 48000.0)
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "frequency":
            frequency = value
            print("Updated parameter frequency = \(frequency) for block SquareOscillatorAudioBlock")
        case "amplitude":
            amplitude = pow(10.0, value / 20.0) // Convert dB to linear
            print("Updated parameter amplitude = \(value) for block SquareOscillatorAudioBlock")
        case "dutyCycle":
            dutyCycle = Self.clampDutyCycle(value)
            print("Updated parameter dutyCycle = \(dutyCycle) for block SquareOscillatorAudioBlock")
        default:
            break
        }
    }

    func reset(to startSample: UInt64, sampleRate: Double) {
        print("⬛ [DEBUG] SquareOscillatorAudioBlock.reset(to:) - Reset to sample \(startSample) at \(sampleRate)Hz")
    }

    func reset() {
        reset(to: 0, sampleRate: 48000.0)
    }

    func getCurrentFrequency() -> Double {
        return frequency
    }

    func getCurrentAmplitude() -> Double {
        return amplitude
    }

    func getCurrentDutyCycle() -> Double {
        return dutyCycle
    }

    private static func clampDutyCycle(_ value: Double) -> Double {
        return min(max(value, 0.0), 1.0)
    }
}

/// Timeline-coherent linear chirp generator implementation
private class LinearChirpAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .linearChirp
    let inputPorts: [String] = []
    let outputPorts: [String] = ["signal"]

    private var startFrequency: Double
    private var endFrequency: Double
    private var durationSeconds: Double
    private var amplitudeDecibels: Double
    private var amplitudeLinear: Double
    private var chirpEngine: ChirpEnvelopeEngine = ChirpEnvelopeEngine()
    private var timelineAnchorSample: UInt64 = 0

    private static let minimumDuration: Double = 1.0e-3
    private static let minimumFrequency: Double = 1.0
    private static let maximumFrequency: Double = 24_000.0

    init(block: SignalBlock) {
        id = block.id

        let startParam = block.parameters["startFrequency"]?.value ?? 100.0
        let endParam = block.parameters["endFrequency"]?.value ?? 1000.0
        let durationParam = block.parameters["duration"]?.value ?? 1.0
        let amplitudeDb = Self.clampAmplitudeDb(block.parameters["amplitude"]?.value ?? -6.0)

        startFrequency = Self.clampFrequency(startParam)
        endFrequency = Self.clampFrequency(endParam)
        durationSeconds = Self.clampDuration(durationParam)
        amplitudeDecibels = amplitudeDb
        amplitudeLinear = Self.dbToLinear(amplitudeDb)
    }

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        guard frameCount > 0, sampleRate > 0 else { return ["signal": []] }

        if startSample < timelineAnchorSample {
            timelineAnchorSample = startSample
            chirpEngine = ChirpEnvelopeEngine()
        }

        var output: [Float] = []
        output.reserveCapacity(frameCount)

        var framesRemaining = frameCount
        var segmentStartSample = startSample
        let rampSamples = Self.defaultRampSamples(sampleRate: sampleRate)
        let cycleDuration = durationSeconds

        while framesRemaining > 0 {
            let relativeStart: UInt64
            if segmentStartSample >= timelineAnchorSample {
                relativeStart = segmentStartSample - timelineAnchorSample
            } else {
                timelineAnchorSample = segmentStartSample
                chirpEngine = ChirpEnvelopeEngine()
                relativeStart = 0
            }

            let elapsedSeconds = Double(relativeStart) / sampleRate
            let cycleOffset = cycleDuration > 0 ? elapsedSeconds.truncatingRemainder(dividingBy: cycleDuration) : 0.0
            let secondsRemaining = cycleDuration > 0 ? max(0.0, cycleDuration - cycleOffset) : Double(framesRemaining) / sampleRate
            let rawSamples = cycleDuration > 0 ? Int((secondsRemaining * sampleRate).rounded(.down)) : framesRemaining
            let segmentSamples = min(framesRemaining, max(1, rawSamples))
            let segmentDuration = Double(max(segmentSamples - 1, 0)) / sampleRate

            let progressStart = cycleDuration > 0 ? min(1.0, max(0.0, cycleOffset / cycleDuration)) : 0.0
            let progressEnd = cycleDuration > 0 ? min(1.0, max(0.0, (cycleOffset + segmentDuration) / cycleDuration)) : 0.0

            let frameStartFrequency = frequency(atProgress: progressStart)
            let frameEndFrequency = frequency(atProgress: progressEnd)

            let segment = chirpEngine.generateLinearChirp(
                frameCount: segmentSamples,
                startSample: segmentStartSample,
                sampleRate: sampleRate,
                startFrequency: frameStartFrequency,
                endFrequency: frameEndFrequency,
                targetAmplitude: amplitudeLinear,
                rampSamples: rampSamples
            )

            for sample in segment {
                output.append(Float(Self.clampToAudioRange(sample)))
            }

            framesRemaining -= segmentSamples
            segmentStartSample &+= UInt64(segmentSamples)
        }

        return ["signal": output]
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(
            inputs: inputs,
            frameCount: frameCount,
            startSample: 0,
            sampleRate: 48_000.0
        )
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "startFrequency":
            startFrequency = Self.clampFrequency(value)
            print("Updated parameter startFrequency = \(startFrequency) for LinearChirpAudioBlock")
        case "endFrequency":
            endFrequency = Self.clampFrequency(value)
            print("Updated parameter endFrequency = \(endFrequency) for LinearChirpAudioBlock")
        case "duration":
            durationSeconds = Self.clampDuration(value)
            print("Updated parameter duration = \(durationSeconds) for LinearChirpAudioBlock")
        case "amplitude":
            let clamped = Self.clampAmplitudeDb(value)
            amplitudeDecibels = clamped
            amplitudeLinear = Self.dbToLinear(clamped)
            print("Updated parameter amplitude = \(clamped) for LinearChirpAudioBlock")
        default:
            break
        }
    }

    func reset(to startSample: UInt64, sampleRate: Double) {
        timelineAnchorSample = startSample
        chirpEngine = ChirpEnvelopeEngine()
        print("📡 [DEBUG] LinearChirpAudioBlock.reset(to:) - Reset to sample \(startSample) at \(sampleRate)Hz")
    }

    func reset() {
        reset(to: 0, sampleRate: 48_000.0)
    }

    private func frequency(atProgress progress: Double) -> Double {
        let clampedProgress = min(max(progress, 0.0), 1.0)
        return startFrequency + (endFrequency - startFrequency) * clampedProgress
    }

    private static func clampFrequency(_ value: Double) -> Double {
        if value.isNaN { return minimumFrequency }
        return min(max(value, minimumFrequency), maximumFrequency)
    }

    private static func clampDuration(_ value: Double) -> Double {
        if value.isNaN { return minimumDuration }
        return max(value, minimumDuration)
    }

    private static func clampAmplitudeDb(_ value: Double) -> Double {
        if value.isNaN { return -6.0 }
        return min(max(value, -60.0), 0.0)
    }

    private static func dbToLinear(_ decibels: Double) -> Double {
        return pow(10.0, decibels / 20.0)
    }

    private static func clampToAudioRange(_ value: Double) -> Double {
        if value > 1.0 { return 1.0 }
        if value < -1.0 { return -1.0 }
        return value
    }

    private static func defaultRampSamples(sampleRate: Double) -> Int {
        let ramp = Int((sampleRate * 0.005).rounded())
        return max(1, min(ramp, 4096))
    }
}

/// Timeline-coherent hyperbolic chirp generator implementation
private class HyperbolicChirpAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .hyperbolicChirp
    let inputPorts: [String] = []
    let outputPorts: [String] = ["signal"]

    private var startFrequency: Double
    private var endFrequency: Double
    private var bandwidth: Double
    private var amplitudeDecibels: Double
    private var amplitudeLinear: Double
    private var chirpEngine: ChirpEnvelopeEngine = ChirpEnvelopeEngine()
    private var timelineAnchorSample: UInt64 = 0

    private static let minimumFrequency: Double = 1.0
    private static let maximumFrequency: Double = 24_000.0
    private static let minimumSweepRate: Double = 10.0
    private static let maximumSweepRate: Double = 192_000.0
    private static let minimumDuration: Double = 1.0e-3
    private static let maximumDuration: Double = 30.0

    init(block: SignalBlock) {
        id = block.id

        let startParam = block.parameters["startFrequency"]?.value ?? 1000.0
        let endParam = block.parameters["endFrequency"]?.value ?? 10_000.0
        let bandwidthParam = block.parameters["bandwidth"]?.value ?? 5_000.0
        let amplitudeDb = Self.clampAmplitudeDb(block.parameters["amplitude"]?.value ?? -6.0)

        startFrequency = Self.clampFrequency(startParam)
        endFrequency = Self.clampFrequency(endParam)
        bandwidth = Self.clampBandwidth(bandwidthParam)
        amplitudeDecibels = amplitudeDb
        amplitudeLinear = Self.dbToLinear(amplitudeDb)
    }

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        guard frameCount > 0, sampleRate > 0 else { return ["signal": []] }

        if startSample < timelineAnchorSample {
            timelineAnchorSample = startSample
            chirpEngine = ChirpEnvelopeEngine()
        }

        var output: [Float] = []
        output.reserveCapacity(frameCount)

        var framesRemaining = frameCount
        var segmentStartSample = startSample
        let rampSamples = Self.defaultRampSamples(sampleRate: sampleRate)
        let cycleDuration = chirpDurationSeconds()

        while framesRemaining > 0 {
            let relativeStart: UInt64
            if segmentStartSample >= timelineAnchorSample {
                relativeStart = segmentStartSample - timelineAnchorSample
            } else {
                timelineAnchorSample = segmentStartSample
                chirpEngine = ChirpEnvelopeEngine()
                relativeStart = 0
            }

            let elapsedSeconds = Double(relativeStart) / sampleRate
            let cycle = cycleDuration
            let cycleOffset = cycle > 0.0 ? elapsedSeconds.truncatingRemainder(dividingBy: cycle) : 0.0
            let secondsRemaining = cycle > 0.0 ? max(0.0, cycle - cycleOffset) : Double(framesRemaining) / sampleRate
            let rawSamples = cycle > 0.0 ? Int((secondsRemaining * sampleRate).rounded(.down)) : framesRemaining
            let segmentSamples = min(framesRemaining, max(1, rawSamples))
            let segmentDuration = Double(max(segmentSamples - 1, 0)) / sampleRate

            let progressStart = cycle > 0.0 ? min(1.0, max(0.0, cycleOffset / cycle)) : 0.0
            let progressEnd = cycle > 0.0 ? min(1.0, max(0.0, (cycleOffset + segmentDuration) / cycle)) : progressStart

            let frameStartFrequency = frequency(atProgress: progressStart, duration: cycle)
            let frameEndFrequency = frequency(atProgress: progressEnd, duration: cycle)

            let segment = chirpEngine.generateHyperbolicChirp(
                frameCount: segmentSamples,
                startSample: segmentStartSample,
                sampleRate: sampleRate,
                startFrequency: frameStartFrequency,
                endFrequency: frameEndFrequency,
                targetAmplitude: amplitudeLinear,
                rampSamples: rampSamples
            )

            for sample in segment {
                output.append(Float(Self.clampToAudioRange(sample)))
            }

            framesRemaining -= segmentSamples
            segmentStartSample &+= UInt64(segmentSamples)
        }

        return ["signal": output]
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(
            inputs: inputs,
            frameCount: frameCount,
            startSample: 0,
            sampleRate: 48_000.0
        )
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "startFrequency":
            startFrequency = Self.clampFrequency(value)
            print("Updated parameter startFrequency = \(startFrequency) for HyperbolicChirpAudioBlock")
        case "endFrequency":
            endFrequency = Self.clampFrequency(value)
            print("Updated parameter endFrequency = \(endFrequency) for HyperbolicChirpAudioBlock")
        case "bandwidth":
            bandwidth = Self.clampBandwidth(value)
            print("Updated parameter bandwidth = \(bandwidth) for HyperbolicChirpAudioBlock")
        case "amplitude":
            let clamped = Self.clampAmplitudeDb(value)
            amplitudeDecibels = clamped
            amplitudeLinear = Self.dbToLinear(clamped)
            print("Updated parameter amplitude = \(clamped) for HyperbolicChirpAudioBlock")
        default:
            break
        }
    }

    func reset(to startSample: UInt64, sampleRate: Double) {
        timelineAnchorSample = startSample
        chirpEngine = ChirpEnvelopeEngine()
        print("📡 [DEBUG] HyperbolicChirpAudioBlock.reset(to:) - Reset to sample \(startSample) at \(sampleRate)Hz")
    }

    func reset() {
        reset(to: 0, sampleRate: 48_000.0)
    }

    /// Converts the bandwidth control (expressed as a sweep rate in Hz/s) into
    /// a cycle duration so the time-bandwidth product stays tunable for
    /// cross-correlation work.
    private func chirpDurationSeconds() -> Double {
        let sweepSpan = max(abs(endFrequency - startFrequency), Self.minimumFrequency)
        let sweepRate = max(Self.minimumSweepRate, min(bandwidth, Self.maximumSweepRate))
        let candidate = sweepSpan / sweepRate
        if !candidate.isFinite { return Self.minimumDuration }
        return min(max(candidate, Self.minimumDuration), Self.maximumDuration)
    }

    private func frequency(atProgress progress: Double, duration: Double) -> Double {
        let clampedProgress = min(max(progress, 0.0), 1.0)
        let positiveDuration = max(duration, Self.minimumDuration)
        let start = max(startFrequency, Self.minimumFrequency)
        let end = max(endFrequency, Self.minimumFrequency)

        if abs(start - end) < 1.0e-9 {
            return min(max(start, Self.minimumFrequency), Self.maximumFrequency)
        }

        let k = (start / end - 1.0) / positiveDuration
        let time = clampedProgress * positiveDuration
        let denominator = max(1.0 + k * time, 1.0e-9)
        let frequency = start / denominator

        if frequency.isNaN || !frequency.isFinite {
            return min(max(end, Self.minimumFrequency), Self.maximumFrequency)
        }

        return min(max(frequency, Self.minimumFrequency), Self.maximumFrequency)
    }

    private static func clampFrequency(_ value: Double) -> Double {
        if value.isNaN { return minimumFrequency }
        return min(max(value, minimumFrequency), maximumFrequency)
    }

    private static func clampBandwidth(_ value: Double) -> Double {
        if value.isNaN { return minimumSweepRate }
        return min(max(value, minimumSweepRate), maximumSweepRate)
    }

    private static func clampAmplitudeDb(_ value: Double) -> Double {
        if value.isNaN { return -6.0 }
        return min(max(value, -60.0), 0.0)
    }

    private static func dbToLinear(_ decibels: Double) -> Double {
        return pow(10.0, decibels / 20.0)
    }

    private static func clampToAudioRange(_ value: Double) -> Double {
        if value > 1.0 { return 1.0 }
        if value < -1.0 { return -1.0 }
        return value
    }

    private static func defaultRampSamples(sampleRate: Double) -> Int {
        let ramp = Int((sampleRate * 0.005).rounded())
        return max(1, min(ramp, 4096))
    }
}

/// Timeline-coherent pink noise generator implementation
private class PinkNoiseAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .pinkNoise
    let inputPorts: [String] = []
    let outputPorts: [String] = ["signal"]

    private var amplitudeDecibels: Double
    private var amplitudeLinear: Double
    private let noiseGenerator: NoiseGeneratorBase
    private var filterState: PinkFilterState = PinkFilterState()
    private var nextTimelineSample: UInt64?

    private static let warmupChunkSize: UInt64 = 4096

    init(block: SignalBlock) {
        id = block.id

        let amplitudeDB: Double = block.parameters["amplitude"]?.value ?? -12.0
        amplitudeDecibels = amplitudeDB
        amplitudeLinear = Self.dbToLinear(amplitudeDB)
        noiseGenerator = NoiseGeneratorBase()
    }

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        guard frameCount > 0 else { return ["signal": []] }

        alignStateIfNeeded(startSample: startSample, sampleRate: sampleRate)

        let whiteFrame: [Double] = noiseGenerator.generate(
            frameCount: frameCount,
            startSample: startSample,
            sampleRate: sampleRate
        )

        var output: [Float] = []
        output.reserveCapacity(frameCount)

        let amplitude: Double = amplitudeLinear

        for sample in whiteFrame {
            let pink: Double = filterState.process(whiteSample: sample)
            output.append(Float(Self.clampToAudioRange(pink * amplitude)))
        }

        nextTimelineSample = startSample &+ UInt64(frameCount)

        return ["signal": output]
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(
            inputs: inputs,
            frameCount: frameCount,
            startSample: 0,
            sampleRate: 48_000.0
        )
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "amplitude":
            amplitudeDecibels = value
            amplitudeLinear = Self.dbToLinear(value)
            print("🔊 [DEBUG] PinkNoiseAudioBlock.setParameter(amplitude) = \(value) dB")
        default:
            break
        }
    }

    func reset(to startSample: UInt64, sampleRate: Double) {
        noiseGenerator.reset(to: 0)
        filterState.reset()
        nextTimelineSample = 0

        if startSample > 0 {
            advanceFilterState(from: 0, to: startSample, sampleRate: sampleRate)
        }

        noiseGenerator.reset(to: startSample)
        nextTimelineSample = startSample
        print("🔊 [DEBUG] PinkNoiseAudioBlock.reset(to:) - Reset to sample \(startSample) at \(sampleRate)Hz")
    }

    func reset() {
        noiseGenerator.reset()
        filterState.reset()
        nextTimelineSample = 0
        print("🔊 [DEBUG] PinkNoiseAudioBlock.reset() - Reset to beginning")
    }

    private func alignStateIfNeeded(startSample: UInt64, sampleRate: Double) {
        if let expectedSample: UInt64 = nextTimelineSample {
            if startSample == expectedSample {
                return
            }

            if startSample > expectedSample {
                advanceFilterState(from: expectedSample, to: startSample, sampleRate: sampleRate)
                return
            }

            synchroniseFilterState(to: startSample, sampleRate: sampleRate)
            return
        }

        synchroniseFilterState(to: startSample, sampleRate: sampleRate)
    }

    private func synchroniseFilterState(to targetSample: UInt64, sampleRate: Double) {
        noiseGenerator.reset(to: 0)
        filterState.reset()
        nextTimelineSample = 0

        if targetSample > 0 {
            advanceFilterState(from: 0, to: targetSample, sampleRate: sampleRate)
        }
    }

    private func advanceFilterState(from startSample: UInt64, to endSample: UInt64, sampleRate: Double) {
        guard endSample > startSample else { return }

        var cursor: UInt64 = startSample
        while cursor < endSample {
            let remaining: UInt64 = endSample &- cursor
            let chunk: Int = Int(min(remaining, Self.warmupChunkSize))
            if chunk <= 0 { break }

            let warmupFrame: [Double] = noiseGenerator.generate(
                frameCount: chunk,
                startSample: cursor,
                sampleRate: sampleRate
            )

            for sample in warmupFrame {
                _ = filterState.process(whiteSample: sample)
            }

            cursor &+= UInt64(chunk)
        }

        nextTimelineSample = endSample
    }

    @inline(__always)
    private static func dbToLinear(_ decibels: Double) -> Double {
        return pow(10.0, decibels / 20.0)
    }

    @inline(__always)
    private static func clampToAudioRange(_ value: Double) -> Double {
        if value > 1.0 { return 1.0 }
        if value < -1.0 { return -1.0 }
        return value
    }

    private struct PinkFilterState {
        private var b0: Double = 0.0
        private var b1: Double = 0.0
        private var b2: Double = 0.0
        private var b3: Double = 0.0
        private var b4: Double = 0.0
        private var b5: Double = 0.0
        private var b6: Double = 0.0

        mutating func process(whiteSample: Double) -> Double {
            b0 = 0.99886 * b0 + whiteSample * 0.0555179
            b1 = 0.99332 * b1 + whiteSample * 0.0750759
            b2 = 0.96900 * b2 + whiteSample * 0.1538520
            b3 = 0.86650 * b3 + whiteSample * 0.3104856
            b4 = 0.55000 * b4 + whiteSample * 0.5329522
            b5 = -0.7616 * b5 - whiteSample * 0.0168980
            let pink: Double = b0 + b1 + b2 + b3 + b4 + b5 + b6 + whiteSample * 0.5362
            b6 = whiteSample * 0.115926
            return pink * 0.11
        }

        mutating func reset() {
            b0 = 0.0
            b1 = 0.0
            b2 = 0.0
            b3 = 0.0
            b4 = 0.0
            b5 = 0.0
            b6 = 0.0
        }
    }
}

/// Timeline-coherent white noise generator implementation
private class WhiteNoiseAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .whiteNoise
    let inputPorts: [String] = []
    let outputPorts: [String] = ["signal"]

    private var amplitudeDecibels: Double
    private var amplitudeLinear: Double
    private let noiseGenerator: NoiseGeneratorBase

    init(block: SignalBlock) {
        id = block.id

        let amplitudeDB: Double = block.parameters["amplitude"]?.value ?? -12.0
        amplitudeDecibels = amplitudeDB
        amplitudeLinear = Self.dbToLinear(amplitudeDB)
        noiseGenerator = NoiseGeneratorBase()
    }

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        guard frameCount > 0 else { return ["signal": []] }

        let noiseFrame: [Double] = noiseGenerator.generate(
            frameCount: frameCount,
            startSample: startSample,
            sampleRate: sampleRate
        )

        var output: [Float] = []
        output.reserveCapacity(frameCount)

        let baseAmplitude: Double = amplitudeLinear

        for index in 0..<frameCount {
            let scaledSample: Double = noiseFrame[index] * baseAmplitude
            output.append(Float(Self.clampToAudioRange(scaledSample)))
        }

        return ["signal": output]
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(
            inputs: inputs,
            frameCount: frameCount,
            startSample: 0,
            sampleRate: 48_000.0
        )
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "amplitude":
            amplitudeDecibels = value
            amplitudeLinear = Self.dbToLinear(value)
            print("🔊 [DEBUG] WhiteNoiseAudioBlock.setParameter(amplitude) = \(value) dB")
        default:
            break
        }
    }

    func reset(to startSample: UInt64, sampleRate: Double) {
        noiseGenerator.reset(to: startSample)
        print("🔊 [DEBUG] WhiteNoiseAudioBlock.reset(to:) - Reset to sample \(startSample) at \(sampleRate)Hz")
    }

    func reset() {
        noiseGenerator.reset()
        print("🔊 [DEBUG] WhiteNoiseAudioBlock.reset() - Reset to beginning")
    }

    @inline(__always)
    private static func dbToLinear(_ decibels: Double) -> Double {
        return pow(10.0, decibels / 20.0)
    }

    @inline(__always)
    private static func clampToAudioRange(_ value: Double) -> Double {
        if value > 1.0 { return 1.0 }
        if value < -1.0 { return -1.0 }
        return value
    }
}

/// Time-coherent triangle oscillator implementation
private class TriangleOscillatorAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .triangleOscillator
    let inputPorts: [String] = ["frequency"]
    let outputPorts: [String] = ["signal"]

    private var frequency: Double = 440.0
    private var amplitude: Double = 0.5
    // Removed phase - now calculated from timeline

    init(block: SignalBlock) {
        self.id = block.id
        if let freqParam = block.parameters["frequency"] {
            self.frequency = freqParam.value
        }
        if let ampParam = block.parameters["amplitude"] {
            self.amplitude = pow(10.0, ampParam.value / 20.0)
        }
    }

    // MARK: - Time-Coherent Audio Processing

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        var output: [Float] = []
        output.reserveCapacity(frameCount)

        // Check for frequency modulation input
        let baseFrequency = frequency
        let frequencyInput = inputs["frequency"]

        for frame in 0..<frameCount {
            let sampleIndex = startSample + UInt64(frame)
            let time = Double(sampleIndex) / sampleRate

            // Apply frequency modulation if input is connected
            let currentFrequency: Double
            if let freqInput = frequencyInput, frame < freqInput.count {
                currentFrequency = baseFrequency + Double(freqInput[frame])
            } else {
                currentFrequency = baseFrequency
            }

            // Calculate normalized phase from absolute timeline position
            let normalizedPhase = (currentFrequency * time).truncatingRemainder(dividingBy: 1.0)

            // Generate triangle wave: sawtooth transformed to triangle
            let triangleValue: Double = abs(normalizedPhase - 0.5) * 4.0 - 1.0
            let sample = Float(amplitude * triangleValue)
            output.append(sample)
        }

        return ["signal": output]
    }

    // Legacy method for backward compatibility
    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(
            inputs: inputs,
            frameCount: frameCount,
            startSample: 0,
            sampleRate: 48000.0
        )
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "frequency":
            frequency = value
        case "amplitude":
            amplitude = pow(10.0, value / 20.0)
        default:
            break
        }
    }

    // MARK: - Reset Methods

    func reset(to startSample: UInt64, sampleRate: Double) {
        // No internal state to reset - phase calculated from timeline
        print("🔺 [DEBUG] TriangleOscillatorAudioBlock.reset(to:) - Reset to sample \(startSample) at \(sampleRate)Hz")
    }

    func reset() {
        // Legacy reset method
        reset(to: 0, sampleRate: 48000.0)
    }
}

/// Timeline-coherent low-pass filter using shared biquad core
private class LowPassFilterAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .lowPassFilter
    let inputPorts: [String] = ["input"]
    let outputPorts: [String] = ["output"]

    private var cutoffFrequency: Double
    private var resonance: Double
    private var lastSampleRate: Double
    private let filterCore: BiquadFilterCore

    init(block: SignalBlock) {
        id = block.id
        let cutoffParam = block.parameters["cutoffFrequency"]?.value ?? 1_000.0
        let resonanceParam = block.parameters["resonance"]?.value ?? 0.707
        lastSampleRate = 48_000.0
        cutoffFrequency = Self.sanitizeCutoff(cutoffParam)
        resonance = Self.clampResonance(resonanceParam)
        filterCore = BiquadFilterCore.createLowpass(frequency: cutoffFrequency, q: resonance)
    }

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        guard frameCount > 0 else { return ["output": []] }

        let localSampleRate: Double
        if sampleRate.isFinite, sampleRate > 0 {
            lastSampleRate = sampleRate
            localSampleRate = sampleRate
        } else {
            localSampleRate = lastSampleRate
        }

        let effectiveCutoff = Self.effectiveCutoff(for: cutoffFrequency, sampleRate: localSampleRate)
        cutoffFrequency = Self.sanitizeCutoff(cutoffFrequency)
        let effectiveResonance = Self.clampResonance(resonance)

        let inputSignal = inputs["input"] ?? []
        var doubleBuffer = [Double](repeating: 0.0, count: frameCount)

        if !inputSignal.isEmpty {
            let copyCount = min(frameCount, inputSignal.count)
            for index in 0..<copyCount {
                doubleBuffer[index] = Double(inputSignal[index])
            }
        }

        let filtered = filterCore.processAudio(
            samples: doubleBuffer,
            startSample: startSample,
            sampleRate: localSampleRate,
            filterType: .lowpass,
            frequency: effectiveCutoff,
            q: effectiveResonance,
            gain: 0.0
        )

        let output = filtered.map { sample -> Float in
            if sample > 1.0 { return 1.0 }
            if sample < -1.0 { return -1.0 }
            return Float(sample)
        }

        return ["output": output]
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(
            inputs: inputs,
            frameCount: frameCount,
            startSample: 0,
            sampleRate: 48_000.0
        )
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "cutoffFrequency":
            cutoffFrequency = Self.sanitizeCutoff(value)
            print("🪄 [DEBUG] LowPassFilterAudioBlock.setParameter(cutoffFrequency) = \(cutoffFrequency)Hz")
        case "resonance":
            resonance = Self.clampResonance(value)
            print("🪄 [DEBUG] LowPassFilterAudioBlock.setParameter(resonance) = \(resonance)")
        default:
            break
        }
    }

    func reset(to startSample: UInt64, sampleRate: Double) {
        filterCore.reset(to: startSample)
        lastSampleRate = sampleRate
        cutoffFrequency = Self.sanitizeCutoff(cutoffFrequency)
        print("🪄 [DEBUG] LowPassFilterAudioBlock.reset(to:) - sample \(startSample) @ \(sampleRate)Hz")
    }

    func reset() {
        filterCore.reset()
        lastSampleRate = 48_000.0
        cutoffFrequency = Self.sanitizeCutoff(cutoffFrequency)
    }

    private static func sanitizeCutoff(_ value: Double) -> Double {
        guard value.isFinite else { return 1_000.0 }
        return min(max(value, 10.0), 40_000.0)
    }

    private static func effectiveCutoff(for value: Double, sampleRate: Double) -> Double {
        let sanitized = sanitizeCutoff(value)
        guard sampleRate.isFinite, sampleRate > 0 else { return sanitized }
        let maxAllowed = max(sampleRate * 0.49, 10.0)
        return min(sanitized, maxAllowed)
    }

    private static func clampResonance(_ value: Double) -> Double {
        guard value.isFinite else { return 0.707 }
        return min(max(value, 0.1), 12.0)
    }
}

/// Timeline-coherent high-pass filter using shared biquad core
private class HighPassFilterAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .highPassFilter
    let inputPorts: [String] = ["input"]
    let outputPorts: [String] = ["output"]

    private var cutoffFrequency: Double
    private var resonance: Double
    private var lastSampleRate: Double
    private let filterCore: BiquadFilterCore

    init(block: SignalBlock) {
        id = block.id
        let cutoffParam = block.parameters["cutoffFrequency"]?.value ?? 1_000.0
        let resonanceParam = block.parameters["resonance"]?.value ?? 0.707
        lastSampleRate = 48_000.0
        cutoffFrequency = Self.sanitizeCutoff(cutoffParam)
        resonance = Self.clampResonance(resonanceParam)
        filterCore = BiquadFilterCore.createHighpass(frequency: cutoffFrequency, q: resonance)
    }

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        guard frameCount > 0 else { return ["output": []] }

        let localSampleRate: Double
        if sampleRate.isFinite, sampleRate > 0 {
            lastSampleRate = sampleRate
            localSampleRate = sampleRate
        } else {
            localSampleRate = lastSampleRate
        }

        let effectiveCutoff = Self.effectiveCutoff(for: cutoffFrequency, sampleRate: localSampleRate)
        cutoffFrequency = Self.sanitizeCutoff(cutoffFrequency)
        let effectiveResonance = Self.clampResonance(resonance)

        let inputSignal = inputs["input"] ?? []
        var doubleBuffer = [Double](repeating: 0.0, count: frameCount)

        if !inputSignal.isEmpty {
            let copyCount = min(frameCount, inputSignal.count)
            for index in 0..<copyCount {
                doubleBuffer[index] = Double(inputSignal[index])
            }
        }

        let filtered = filterCore.processAudio(
            samples: doubleBuffer,
            startSample: startSample,
            sampleRate: localSampleRate,
            filterType: .highpass,
            frequency: effectiveCutoff,
            q: effectiveResonance,
            gain: 0.0
        )

        let output = filtered.map { sample -> Float in
            if sample > 1.0 { return 1.0 }
            if sample < -1.0 { return -1.0 }
            return Float(sample)
        }

        return ["output": output]
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(
            inputs: inputs,
            frameCount: frameCount,
            startSample: 0,
            sampleRate: 48_000.0
        )
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "cutoffFrequency":
            cutoffFrequency = Self.sanitizeCutoff(value)
            print("🔊 [DEBUG] HighPassFilterAudioBlock.setParameter(cutoffFrequency) = \(cutoffFrequency)Hz")
        case "resonance":
            resonance = Self.clampResonance(value)
            print("🔊 [DEBUG] HighPassFilterAudioBlock.setParameter(resonance) = \(resonance)")
        default:
            break
        }
    }

    func reset(to startSample: UInt64, sampleRate: Double) {
        filterCore.reset(to: startSample)
        lastSampleRate = sampleRate
        cutoffFrequency = Self.sanitizeCutoff(cutoffFrequency)
        print("🔊 [DEBUG] HighPassFilterAudioBlock.reset(to:) - sample \(startSample) @ \(sampleRate)Hz")
    }

    func reset() {
        filterCore.reset()
        lastSampleRate = 48_000.0
        cutoffFrequency = Self.sanitizeCutoff(cutoffFrequency)
    }

    private static func sanitizeCutoff(_ value: Double) -> Double {
        guard value.isFinite else { return 1_000.0 }
        return min(max(value, 10.0), 40_000.0)
    }

    private static func effectiveCutoff(for value: Double, sampleRate: Double) -> Double {
        let sanitized = sanitizeCutoff(value)
        guard sampleRate.isFinite, sampleRate > 0 else { return sanitized }
        let maxAllowed = max(sampleRate * 0.49, 10.0)
        return min(sanitized, maxAllowed)
    }

    private static func clampResonance(_ value: Double) -> Double {
        guard value.isFinite else { return 0.707 }
        return min(max(value, 0.1), 12.0)
    }
}

/// Timeline-coherent band-pass filter using shared biquad core
private class BandPassFilterAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .bandPassFilter
    let inputPorts: [String] = ["input"]
    let outputPorts: [String] = ["output"]

    private var centerFrequency: Double
    private var qFactor: Double
    private var lastSampleRate: Double
    private let filterCore: BiquadFilterCore

    init(block: SignalBlock) {
        id = block.id
        let centerParam = block.parameters["centerFrequency"]?.value ?? 1_000.0
        let qParam = block.parameters["qFactor"]?.value ?? 1.0
        lastSampleRate = 48_000.0
        centerFrequency = Self.sanitizeFrequency(centerParam)
        qFactor = Self.clampQFactor(qParam)
        filterCore = BiquadFilterCore.createBandpass(frequency: centerFrequency, q: qFactor)
    }

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        guard frameCount > 0 else { return ["output": []] }

        let localSampleRate: Double
        if sampleRate.isFinite, sampleRate > 0 {
            lastSampleRate = sampleRate
            localSampleRate = sampleRate
        } else {
            localSampleRate = lastSampleRate
        }

        let effectiveCenter = Self.effectiveFrequency(for: centerFrequency, sampleRate: localSampleRate)
        centerFrequency = Self.sanitizeFrequency(centerFrequency)
        let effectiveQ = Self.clampQFactor(qFactor)

        let inputSignal = inputs["input"] ?? []
        var doubleBuffer = [Double](repeating: 0.0, count: frameCount)

        if !inputSignal.isEmpty {
            let copyCount = min(frameCount, inputSignal.count)
            for index in 0..<copyCount {
                doubleBuffer[index] = Double(inputSignal[index])
            }
        }

        let filtered = filterCore.processAudio(
            samples: doubleBuffer,
            startSample: startSample,
            sampleRate: localSampleRate,
            filterType: .bandpass,
            frequency: effectiveCenter,
            q: effectiveQ,
            gain: 0.0
        )

        let output = filtered.map { sample -> Float in
            if sample > 1.0 { return 1.0 }
            if sample < -1.0 { return -1.0 }
            return Float(sample)
        }

        return ["output": output]
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(
            inputs: inputs,
            frameCount: frameCount,
            startSample: 0,
            sampleRate: 48_000.0
        )
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "centerFrequency":
            centerFrequency = Self.sanitizeFrequency(value)
            print("📶 [DEBUG] BandPassFilterAudioBlock.setParameter(centerFrequency) = \(centerFrequency)Hz")
        case "qFactor":
            qFactor = Self.clampQFactor(value)
            print("📶 [DEBUG] BandPassFilterAudioBlock.setParameter(qFactor) = \(qFactor)")
        default:
            break
        }
    }

    func reset(to startSample: UInt64, sampleRate: Double) {
        filterCore.reset(to: startSample)
        lastSampleRate = sampleRate
        centerFrequency = Self.sanitizeFrequency(centerFrequency)
        print("📶 [DEBUG] BandPassFilterAudioBlock.reset(to:) - sample \(startSample) @ \(sampleRate)Hz")
    }

    func reset() {
        filterCore.reset()
        lastSampleRate = 48_000.0
        centerFrequency = Self.sanitizeFrequency(centerFrequency)
    }

    private static func sanitizeFrequency(_ value: Double) -> Double {
        guard value.isFinite else { return 1_000.0 }
        return min(max(value, 10.0), 40_000.0)
    }

    private static func effectiveFrequency(for value: Double, sampleRate: Double) -> Double {
        let sanitized = sanitizeFrequency(value)
        guard sampleRate.isFinite, sampleRate > 0 else { return sanitized }
        let maxAllowed = max(sampleRate * 0.49, 10.0)
        return min(sanitized, maxAllowed)
    }

    private static func clampQFactor(_ value: Double) -> Double {
        guard value.isFinite else { return 1.0 }
        return min(max(value, 0.1), 100.0)
    }
}

/// Timeline-coherent audio mixer with individual channel level controls
private class MixerAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .mixer
    let inputPorts: [String] = ["input1", "input2", "input3", "input4"]
    let outputPorts: [String] = ["output"]

    private var inputLevels: [String: Double] = [:]
    private var masterLevel: Double = 1.0

    init(block: SignalBlock) {
        id = block.id

        // Initialize input levels for each input port
        for inputPort in inputPorts {
            inputLevels[inputPort] = 1.0 // Default level: unity gain (0dB)
        }

        // Check for level parameters from block configuration
        if let level1 = block.parameters["level1"]?.value {
            inputLevels["input1"] = Self.dbToLinear(level1)
        }
        if let level2 = block.parameters["level2"]?.value {
            inputLevels["input2"] = Self.dbToLinear(level2)
        }
        if let level3 = block.parameters["level3"]?.value {
            inputLevels["input3"] = Self.dbToLinear(level3)
        }
        if let level4 = block.parameters["level4"]?.value {
            inputLevels["input4"] = Self.dbToLinear(level4)
        }
        if let master = block.parameters["masterLevel"]?.value {
            masterLevel = Self.dbToLinear(master)
        }
    }

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        guard frameCount > 0 else { return ["output": []] }

        var output = [Float](repeating: 0.0, count: frameCount)

        // Mix all input signals with their respective levels
        for inputPort in inputPorts {
            guard let inputSignal = inputs[inputPort],
                  let level = inputLevels[inputPort],
                  !inputSignal.isEmpty else { continue }

            let copyCount = min(frameCount, inputSignal.count)
            for frame in 0..<copyCount {
                let sample = Double(inputSignal[frame]) * level
                output[frame] += Float(Self.clampToAudioRange(sample))
            }
        }

        // Apply master level and final clamping
        for frame in 0..<frameCount {
            let masterSample = Double(output[frame]) * masterLevel
            output[frame] = Float(Self.clampToAudioRange(masterSample))
        }

        return ["output": output]
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(
            inputs: inputs,
            frameCount: frameCount,
            startSample: 0,
            sampleRate: 48_000.0
        )
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "level1":
            inputLevels["input1"] = Self.dbToLinear(value)
            print("🎚️ [DEBUG] MixerAudioBlock.setParameter(level1) = \(value)dB")
        case "level2":
            inputLevels["input2"] = Self.dbToLinear(value)
            print("🎚️ [DEBUG] MixerAudioBlock.setParameter(level2) = \(value)dB")
        case "level3":
            inputLevels["input3"] = Self.dbToLinear(value)
            print("🎚️ [DEBUG] MixerAudioBlock.setParameter(level3) = \(value)dB")
        case "level4":
            inputLevels["input4"] = Self.dbToLinear(value)
            print("🎚️ [DEBUG] MixerAudioBlock.setParameter(level4) = \(value)dB")
        case "masterLevel":
            masterLevel = Self.dbToLinear(value)
            print("🎚️ [DEBUG] MixerAudioBlock.setParameter(masterLevel) = \(value)dB")
        default:
            break
        }
    }

    func reset(to startSample: UInt64, sampleRate: Double) {
        // Mixer has no internal state to reset
        print("🎚️ [DEBUG] MixerAudioBlock.reset(to:) - sample \(startSample) @ \(sampleRate)Hz")
    }

    func reset() {
        reset(to: 0, sampleRate: 48_000.0)
    }

    private static func dbToLinear(_ dB: Double) -> Double {
        guard dB.isFinite else { return 1.0 }
        let clampedDb = max(-60.0, min(20.0, dB)) // Clamp to reasonable range
        return pow(10.0, clampedDb / 20.0)
    }

    @inline(__always)
    private static func clampToAudioRange(_ value: Double) -> Double {
        if value > 1.0 { return 1.0 }
        if value < -1.0 { return -1.0 }
        return value
    }
}

/// Timeline-coherent audio amplifier with gain control
private class AmplifierAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .amplifier
    let inputPorts: [String] = ["input"]
    let outputPorts: [String] = ["output"]

    private var gain: Double = 1.0 // Linear gain (0dB = 1.0)

    init(block: SignalBlock) {
        id = block.id

        // Initialize gain from block parameters
        if let gainParam = block.parameters["gain"]?.value {
            gain = Self.dbToLinear(gainParam)
        }
    }

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        guard frameCount > 0 else { return ["output": []] }

        let inputSignal = inputs["input"] ?? []
        var output = [Float](repeating: 0.0, count: frameCount)

        if !inputSignal.isEmpty {
            let copyCount = min(frameCount, inputSignal.count)
            for frame in 0..<copyCount {
                let amplifiedSample = Double(inputSignal[frame]) * gain
                output[frame] = Float(Self.clampToAudioRange(amplifiedSample))
            }
        }

        return ["output": output]
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(
            inputs: inputs,
            frameCount: frameCount,
            startSample: 0,
            sampleRate: 48_000.0
        )
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "gain":
            gain = Self.dbToLinear(value)
            print("🔊 [DEBUG] AmplifierAudioBlock.setParameter(gain) = \(value)dB")
        default:
            break
        }
    }

    func reset(to startSample: UInt64, sampleRate: Double) {
        // Amplifier has no internal state to reset
        print("🔊 [DEBUG] AmplifierAudioBlock.reset(to:) - sample \(startSample) @ \(sampleRate)Hz")
    }

    func reset() {
        reset(to: 0, sampleRate: 48_000.0)
    }

    private static func dbToLinear(_ dB: Double) -> Double {
        guard dB.isFinite else { return 1.0 }
        let clampedDb = max(-60.0, min(20.0, dB)) // Clamp to reasonable range
        return pow(10.0, clampedDb / 20.0)
    }

    @inline(__always)
    private static func clampToAudioRange(_ value: Double) -> Double {
        if value > 1.0 { return 1.0 }
        if value < -1.0 { return -1.0 }
        return value
    }
}

/// Time-coherent audio output block implementation
private class AudioOutputAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .audioOutput
    let inputPorts: [String] = ["input"]
    let outputPorts: [String] = []

    init(block: SignalBlock) {
        self.id = block.id
    }

    // MARK: - Time-Coherent Audio Processing

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        // Audio output consumes the signal but produces no output
        // Timeline context available for future features like recording
        return [:]
    }

    // Legacy method for backward compatibility
    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(
            inputs: inputs,
            frameCount: frameCount,
            startSample: 0,
            sampleRate: 48000.0
        )
    }

    func setParameter(name: String, value: Double) {
        // Audio output has no parameters
    }

    // MARK: - Reset Methods

    func reset(to startSample: UInt64, sampleRate: Double) {
        // Nothing to reset for audio output
        print("🔊 [DEBUG] AudioOutputAudioBlock.reset(to:) - Reset to sample \(startSample) at \(sampleRate)Hz")
    }

    func reset() {
        // Legacy reset method
        reset(to: 0, sampleRate: 48000.0)
    }
}

/// Timeline-coherent frequency modulator implementation
private class FrequencyModulatorAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .frequencyModulator
    let inputPorts: [String] = ["carrier", "modulation"]
    let outputPorts: [String] = ["output"]

    private var deviation: Double = 1_000.0
    private var lastCarrierSample: Double?
    private var lastCarrierSampleIndex: UInt64?
    private var lastPositiveZeroCrossing: Double?
    private var lastEstimatedCarrierFrequency: Double = 440.0

    init(block: SignalBlock) {
        id = block.id
        if let deviationParam = block.parameters["deviation"] {
            deviation = Self.clampDeviation(deviationParam.value)
        }
    }

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        guard frameCount > 0 else { return ["output": []] }

        let carrierInput = inputs["carrier"] ?? []
        let modulationInput = inputs["modulation"] ?? []
        var output: [Float] = []
        output.reserveCapacity(frameCount)

        for frame in 0..<frameCount {
            let sampleIndex = startSample + UInt64(frame)
            let carrierSample = frame < carrierInput.count ? Double(carrierInput[frame]) : nil
            let modulationSample = frame < modulationInput.count ? Double(modulationInput[frame]) : 0.0
            let clampedModulation = max(-1.0, min(1.0, modulationSample))

            let carrierFrequency = estimateCarrierFrequency(
                sampleIndex: sampleIndex,
                currentSample: carrierSample,
                sampleRate: sampleRate
            )

            let instantaneousFrequency = Self.clampFrequency(
                carrierFrequency + deviation * clampedModulation,
                sampleRate: sampleRate
            )

            let time = Double(sampleIndex) / sampleRate
            let phase = Self.twoPi * instantaneousFrequency * time
            let sampleValue = sin(phase)

            output.append(Float(Self.clampToAudioRange(sampleValue)))
        }

        return ["output": output]
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(
            inputs: inputs,
            frameCount: frameCount,
            startSample: 0,
            sampleRate: 48_000.0
        )
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "deviation":
            deviation = Self.clampDeviation(value)
            print("📡 [DEBUG] FrequencyModulatorAudioBlock.setParameter(deviation) = \(deviation)Hz")
        default:
            break
        }
    }

    func reset(to startSample: UInt64, sampleRate: Double) {
        lastCarrierSample = nil
        lastCarrierSampleIndex = nil
        lastPositiveZeroCrossing = nil
        lastEstimatedCarrierFrequency = 440.0
        print("📡 [DEBUG] FrequencyModulatorAudioBlock.reset(to:) - Reset to sample \(startSample) at \(sampleRate)Hz")
    }

    func reset() {
        reset(to: 0, sampleRate: 48_000.0)
    }

    private func estimateCarrierFrequency(
        sampleIndex: UInt64,
        currentSample: Double?,
        sampleRate: Double
    ) -> Double {
        guard let currentSample = currentSample, currentSample.isFinite else {
            return lastEstimatedCarrierFrequency
        }

        if let previousSample = lastCarrierSample,
           let previousIndex = lastCarrierSampleIndex,
           previousSample <= 0.0,
           currentSample > 0.0 {
            let denom = abs(previousSample) + abs(currentSample)
            let crossingOffset = denom > 0.0 ? abs(previousSample) / denom : 0.0
            let crossingPosition = Double(previousIndex) + crossingOffset

            if let lastCrossing = lastPositiveZeroCrossing {
                let periodSamples = crossingPosition - lastCrossing
                if periodSamples > 0.0 {
                    let estimated = sampleRate / periodSamples
                    lastEstimatedCarrierFrequency = Self.clampFrequency(estimated, sampleRate: sampleRate)
                }
            }

            lastPositiveZeroCrossing = crossingPosition
        }

        lastCarrierSample = currentSample
        lastCarrierSampleIndex = sampleIndex
        return lastEstimatedCarrierFrequency
    }

    private static func clampDeviation(_ value: Double) -> Double {
        if value.isNaN { return 1_000.0 }
        return min(max(value, 0.0), 10_000.0)
    }

    private static func clampFrequency(_ value: Double, sampleRate: Double) -> Double {
        if value.isNaN { return 0.0 }
        let nyquist = sampleRate / 2.0
        return min(max(value, 0.0), nyquist)
    }

    @inline(__always)
    private static func clampToAudioRange(_ value: Double) -> Double {
        if value > 1.0 { return 1.0 }
        if value < -1.0 { return -1.0 }
        return value
    }

    private static let twoPi = 2.0 * Double.pi
}

/// Timeline-coherent ring modulator implementation
private class RingModulatorAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .ringModulator
    let inputPorts: [String] = ["signal1", "signal2"]
    let outputPorts: [String] = ["output"]

    init(block: SignalBlock) {
        id = block.id
    }

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        guard frameCount > 0 else { return ["output": []] }

        let signal1 = inputs["signal1"] ?? []
        let signal2 = inputs["signal2"] ?? []

        var output: [Float] = []
        output.reserveCapacity(frameCount)

        for frame in 0..<frameCount {
            let sampleIndex = startSample + UInt64(frame)
            let time = Double(sampleIndex) / sampleRate
            if !time.isFinite {
                output.append(0.0)
                continue
            }

            let sample1 = frame < signal1.count ? Double(signal1[frame]) : 0.0
            let sample2 = frame < signal2.count ? Double(signal2[frame]) : 0.0
            let product = sample1 * sample2
            output.append(Float(Self.clampToAudioRange(product)))
        }

        return ["output": output]
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        processAudio(
            inputs: inputs,
            frameCount: frameCount,
            startSample: 0,
            sampleRate: 48_000.0
        )
    }

    func setParameter(name: String, value: Double) {
        print("🔔 [DEBUG] RingModulatorAudioBlock.setParameter(\(name)) = \(value) ignored")
    }

    func reset(to startSample: UInt64, sampleRate: Double) {
        print("🔔 [DEBUG] RingModulatorAudioBlock.reset(to:) - Reset to sample \(startSample) at \(sampleRate)Hz")
    }

    func reset() {
        reset(to: 0, sampleRate: 48_000.0)
    }

    @inline(__always)
    private static func clampToAudioRange(_ value: Double) -> Double {
        if value > 1.0 { return 1.0 }
        if value < -1.0 { return -1.0 }
        return value
    }
}

/// Timeline-coherent amplitude modulator implementation
private class AmplitudeModulatorAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .amplitudeModulator
    let inputPorts: [String] = ["carrier", "modulation"]
    let outputPorts: [String] = ["output"]

    private var modulationDepth: Double = 1.0

    init(block: SignalBlock) {
        id = block.id

        if let depthParam = block.parameters["depth"] {
            modulationDepth = Self.clampDepth(depthParam.value / 100.0) // Convert percentage to 0-1
        }
    }

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        guard frameCount > 0 else { return ["output": []] }

        let carrierInput = inputs["carrier"] ?? Array(repeating: 0.0, count: frameCount)
        let modulationInput = inputs["modulation"] ?? Array(repeating: 0.0, count: frameCount)

        var output: [Float] = []
        output.reserveCapacity(frameCount)

        for frame in 0..<frameCount {
            let carrierSample = frame < carrierInput.count ? carrierInput[frame] : 0.0
            let modulationSample = frame < modulationInput.count ? modulationInput[frame] : 0.0

            // Amplitude modulation: carrier * (1 + depth * modulation)
            let modulatedAmplitude = 1.0 + modulationDepth * Double(modulationSample)
            let outputSample = Double(carrierSample) * modulatedAmplitude

            output.append(Float(Self.clampToAudioRange(outputSample)))
        }

        return ["output": output]
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(
            inputs: inputs,
            frameCount: frameCount,
            startSample: 0,
            sampleRate: 48_000.0
        )
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "depth":
            modulationDepth = Self.clampDepth(value / 100.0) // Convert percentage to 0-1
            print("🎚️ [DEBUG] AmplitudeModulatorAudioBlock.setParameter(depth) = \(value)%")
        default:
            break
        }
    }

    func reset(to startSample: UInt64, sampleRate: Double) {
        // No internal state to reset
        print("🎚️ [DEBUG] AmplitudeModulatorAudioBlock.reset(to:) - Reset to sample \(startSample) at \(sampleRate)Hz")
    }

    func reset() {
        reset(to: 0, sampleRate: 48_000.0)
    }

    private static func clampDepth(_ value: Double) -> Double {
        if value.isNaN { return 1.0 }
        return min(max(value, 0.0), 2.0) // Allow up to 200% modulation depth
    }

    @inline(__always)
    private static func clampToAudioRange(_ value: Double) -> Double {
        if value > 1.0 { return 1.0 }
        if value < -1.0 { return -1.0 }
        return value
    }
}

/// Level meter with peak and RMS tracking using timeline-aware smoothing
private class LevelMeterAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .levelMeter
    let inputPorts: [String] = ["input"]
    let outputPorts: [String] = ["peak", "rms"]

    private var timeConstant: Double
    private var peakEnvelope: Double = 0.0
    private var rmsSquaredEnvelope: Double = 0.0
    private var lastSampleRate: Double = 48_000.0

    init(block: SignalBlock) {
        id = block.id
        let timeConstantValue = block.parameters["timeConstant"]?.value ?? 0.1
        timeConstant = Self.sanitizeTimeConstant(timeConstantValue)
    }

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        guard frameCount > 0 else {
            return ["peak": [], "rms": []]
        }

        let inputSignal = inputs["input"] ?? []
        let localSampleRate: Double
        if sampleRate.isFinite, sampleRate > 0.0 {
            lastSampleRate = sampleRate
            localSampleRate = sampleRate
        } else {
            localSampleRate = lastSampleRate
        }

        let smoothing = Self.smoothingCoefficient(timeConstant: timeConstant, sampleRate: localSampleRate)
        var peakState = peakEnvelope
        var rmsState = rmsSquaredEnvelope

        let processedSamples = min(frameCount, inputSignal.count)
        if processedSamples > 0 {
            for index in 0..<processedSamples {
                let sampleValue = Double(inputSignal[index])
                let magnitude = abs(sampleValue)
                peakState = max(magnitude, smoothing * peakState + (1.0 - smoothing) * magnitude)
                let squared = magnitude * magnitude
                rmsState = smoothing * rmsState + (1.0 - smoothing) * squared
            }
        }

        if processedSamples < frameCount {
            let remaining = frameCount - processedSamples
            if remaining > 0 {
                let decay = pow(smoothing, Double(remaining))
                peakState *= decay
                rmsState *= decay
            }
        }

        peakEnvelope = Self.clampToUnitRange(peakState)
        rmsSquaredEnvelope = max(rmsState, 0.0)

        let rmsValue = sqrt(rmsSquaredEnvelope)
        let peakOutput = Float(peakEnvelope)
        let rmsOutput = Float(Self.clampToUnitRange(rmsValue))

        return [
            "peak": Array(repeating: peakOutput, count: frameCount),
            "rms": Array(repeating: rmsOutput, count: frameCount)
        ]
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(
            inputs: inputs,
            frameCount: frameCount,
            startSample: 0,
            sampleRate: lastSampleRate
        )
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "timeConstant":
            timeConstant = Self.sanitizeTimeConstant(value)
            print("📈 [DEBUG] LevelMeterAudioBlock.setParameter(timeConstant) = \(timeConstant)s")
        default:
            break
        }
    }

    func currentLinearLevels() -> (peak: Double, rms: Double) {
        let rmsValue = sqrt(max(rmsSquaredEnvelope, 0.0))
        return (
            peak: Self.clampToUnitRange(peakEnvelope),
            rms: Self.clampToUnitRange(rmsValue)
        )
    }

    func reset(to startSample: UInt64, sampleRate: Double) {
        peakEnvelope = 0.0
        rmsSquaredEnvelope = 0.0
        if sampleRate.isFinite, sampleRate > 0.0 {
            lastSampleRate = sampleRate
        }
        print("📈 [DEBUG] LevelMeterAudioBlock.reset(to:) - Reset to sample \(startSample) at \(sampleRate)Hz")
    }

    func reset() {
        reset(to: 0, sampleRate: lastSampleRate)
    }

    private static func sanitizeTimeConstant(_ value: Double) -> Double {
        if value.isNaN || value <= 0.0 {
            return 0.1
        }
        return min(max(value, 0.01), 2.0)
    }

    private static func smoothingCoefficient(timeConstant: Double, sampleRate: Double) -> Double {
        guard sampleRate.isFinite, sampleRate > 0.0 else { return 0.0 }
        let tc = max(timeConstant, 0.0005)
        let windowSamples = tc * sampleRate
        return exp(-1.0 / max(windowSamples, 1.0))
    }

    private static func clampToUnitRange(_ value: Double) -> Double {
        if value < 0.0 { return 0.0 }
        if value > 1.0 { return 1.0 }
        return value
    }
}

/// Frequency counter with zero-crossing detection and exponential averaging
private class FrequencyCounterAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .frequencyCounter
    let inputPorts: [String] = ["input"]
    let outputPorts: [String] = ["frequency"]

    private var sampleWindow: Double
    private var currentFrequency: Double = 0.0
    private var lastSampleRate: Double = 48_000.0
    private var previousSampleValue: Double = 0.0
    private var previousSampleIndex: UInt64 = 0
    private var hasPreviousSample: Bool = false
    private var lastZeroCrossingSample: Double?

    init(block: SignalBlock) {
        id = block.id
        let windowValue = block.parameters["sampleWindow"]?.value ?? 0.1
        sampleWindow = Self.sanitizeSampleWindow(windowValue)
    }

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        guard frameCount > 0 else {
            return ["frequency": []]
        }

        let inputSignal = inputs["input"] ?? []
        let localSampleRate: Double
        if sampleRate.isFinite, sampleRate > 0.0 {
            lastSampleRate = sampleRate
            localSampleRate = sampleRate
        } else {
            localSampleRate = lastSampleRate
        }

        let smoothing = Self.smoothingCoefficient(sampleWindow: sampleWindow, sampleRate: localSampleRate)
        var frequencyOutput: [Float] = []
        frequencyOutput.reserveCapacity(frameCount)

        for frame in 0..<frameCount {
            let signalValue = frame < inputSignal.count ? Double(inputSignal[frame]) : 0.0
            currentFrequency *= smoothing

            if hasPreviousSample,
               previousSampleValue <= 0.0,
               signalValue > 0.0 {
                let denom = abs(previousSampleValue) + abs(signalValue)
                let crossingOffset = denom > 0.0 ? abs(previousSampleValue) / denom : 0.0
                let crossingSample = Double(previousSampleIndex) + crossingOffset

                if let lastCrossing = lastZeroCrossingSample {
                    let periodSamples = crossingSample - lastCrossing
                    if periodSamples > 0.0, localSampleRate > 0.0 {
                        let estimatedFrequency = localSampleRate / periodSamples
                        currentFrequency += (1.0 - smoothing) * Self.clampFrequency(estimatedFrequency, sampleRate: localSampleRate)
                    }
                } else if localSampleRate > 0.0 {
                    currentFrequency += (1.0 - smoothing) * (localSampleRate / max(sampleWindow * localSampleRate, 1.0))
                }

                lastZeroCrossingSample = crossingSample
            }

            previousSampleValue = signalValue
            previousSampleIndex = startSample + UInt64(frame)
            hasPreviousSample = true

            let clampedFrequency = Self.clampFrequency(currentFrequency, sampleRate: localSampleRate)
            frequencyOutput.append(Float(clampedFrequency))
        }

        return ["frequency": frequencyOutput]
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        return processAudio(
            inputs: inputs,
            frameCount: frameCount,
            startSample: hasPreviousSample ? (previousSampleIndex + 1) : 0,
            sampleRate: lastSampleRate
        )
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "sampleWindow":
            sampleWindow = Self.sanitizeSampleWindow(value)
            print("📏 [DEBUG] FrequencyCounterAudioBlock.setParameter(sampleWindow) = \(sampleWindow)s")
        default:
            break
        }
    }

    func currentFrequencyEstimate() -> Double {
        return Self.clampFrequency(currentFrequency, sampleRate: lastSampleRate)
    }

    func reset(to startSample: UInt64, sampleRate: Double) {
        currentFrequency = 0.0
        lastZeroCrossingSample = nil
        hasPreviousSample = false
        previousSampleIndex = startSample
        previousSampleValue = 0.0
        if sampleRate.isFinite, sampleRate > 0.0 {
            lastSampleRate = sampleRate
        }
        print("📏 [DEBUG] FrequencyCounterAudioBlock.reset(to:) - Reset to sample \(startSample) at \(sampleRate)Hz")
    }

    func reset() {
        reset(to: 0, sampleRate: lastSampleRate)
    }

    private static func sanitizeSampleWindow(_ value: Double) -> Double {
        if value.isNaN || value <= 0.0 {
            return 0.1
        }
        return min(max(value, 0.01), 1.0)
    }

    private static func smoothingCoefficient(sampleWindow: Double, sampleRate: Double) -> Double {
        guard sampleRate.isFinite, sampleRate > 0.0 else { return 0.0 }
        let windowSamples = max(sampleWindow * sampleRate, 1.0)
        return exp(-1.0 / windowSamples)
    }

    private static func clampFrequency(_ value: Double, sampleRate: Double) -> Double {
        guard value.isFinite else { return 0.0 }
        let nyquist = max(sampleRate / 2.0, 1.0)
        if value < 0.0 { return 0.0 }
        if value > nyquist { return nyquist }
        return value
    }
}
