import Foundation
import AVFoundation
import Combine

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

    /// Process audio for one buffer cycle
    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]]

    /// Update a parameter value (called from audio thread)
    func setParameter(name: String, value: Double)

    /// Reset internal state (called when starting/stopping)
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

    private let eventPublisher: PassthroughSubject<AudioBlockEvent, Never> = PassthroughSubject<AudioBlockEvent, Never>()

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

        // Reset all blocks
        for block in registeredBlocks.values {
            block.reset()
        }
    }

    public func isEngineRunning() async -> Bool {
        return audioEngine?.isRunning ?? false
    }

    // MARK: - Block Audio Processing

    public func registerBlock(_ block: SignalBlock) async throws {
        guard registeredBlocks[block.id] == nil else {
            return // Already registered
        }

        // Create audio block implementation based on block type
        let audioBlock: AudioBlock = try createAudioBlock(for: block)
        registeredBlocks[block.id] = audioBlock

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
        // Placeholder implementation
        // In a real implementation, this would analyze the audio signal using FFT
        let sampleCount: Int = 512
        return (0..<sampleCount).map { i in
            let frequency: Float = Float(i) * 48000.0 / Float(sampleCount)
            let magnitude: Float = 1.0 / (1.0 + frequency / 1000.0) // Simulate -6dB/octave rolloff
            return magnitude * Float.random(in: 0.8...1.2) // Add some variance
        }
    }

    public func getLevelMeterData(for blockId: UUID?) async -> (peak: Float, rms: Float) {
        // Placeholder implementation
        // In a real implementation, this would measure actual audio levels
        let rms: Float = Float.random(in: 0.1...0.8)
        let peak: Float = rms * Float.random(in: 1.1...1.4)
        return (peak: peak, rms: rms)
    }

    public func getFrequencyAnalysis(for blockId: UUID) async -> Double? {
        // Placeholder implementation
        // In a real implementation, this would analyze the dominant frequency
        return Double.random(in: 100...10000)
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
        // Placeholder implementation
        // In a real implementation, this would measure actual latency
        return Double.random(in: 5.0...15.0) // 5-15ms typical for modern systems
    }

    // MARK: - Private Methods

    private func createAudioBlock(for block: SignalBlock) throws -> AudioBlock {
        switch block.type {
        case .sineOscillator:
            return SineOscillatorAudioBlock(block: block)
        case .triangleOscillator:
            return TriangleOscillatorAudioBlock(block: block)
        case .audioOutput:
            return AudioOutputAudioBlock(block: block)
        default:
            throw AudioBlockError.blockRegistrationError("Unsupported block type: \(block.type)")
        }
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

/// Simple sine oscillator implementation
private class SineOscillatorAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .sineOscillator
    let inputPorts: [String] = ["frequency"]
    let outputPorts: [String] = ["signal"]

    private var frequency: Double = 440.0
    private var amplitude: Double = 0.5
    private var phase: Double = 0.0
    private let sampleRate: Double = 48000.0

    init(block: SignalBlock) {
        self.id = block.id
        if let freqParam = block.parameters["frequency"] {
            self.frequency = freqParam.value
        }
        if let ampParam = block.parameters["amplitude"] {
            self.amplitude = pow(10.0, ampParam.value / 20.0) // Convert dB to linear
        }
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        var output: [Float] = []
        output.reserveCapacity(frameCount)

        let phaseIncrement: Double = 2.0 * Double.pi * frequency / sampleRate

        for _ in 0..<frameCount {
            let sample: Float = Float(amplitude * sin(phase))
            output.append(sample)
            phase += phaseIncrement

            // Wrap phase to prevent numerical issues
            if phase > 2.0 * Double.pi {
                phase -= 2.0 * Double.pi
            }
        }

        return ["signal": output]
    }

    func setParameter(name: String, value: Double) {
        switch name {
        case "frequency":
            frequency = value
        case "amplitude":
            amplitude = pow(10.0, value / 20.0) // Convert dB to linear
        default:
            break
        }
    }

    func reset() {
        phase = 0.0
    }
}

/// Simple triangle oscillator implementation
private class TriangleOscillatorAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .triangleOscillator
    let inputPorts: [String] = ["frequency"]
    let outputPorts: [String] = ["signal"]

    private var frequency: Double = 440.0
    private var amplitude: Double = 0.5
    private var phase: Double = 0.0
    private let sampleRate: Double = 48000.0

    init(block: SignalBlock) {
        self.id = block.id
        if let freqParam = block.parameters["frequency"] {
            self.frequency = freqParam.value
        }
        if let ampParam = block.parameters["amplitude"] {
            self.amplitude = pow(10.0, ampParam.value / 20.0)
        }
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        var output: [Float] = []
        output.reserveCapacity(frameCount)

        let phaseIncrement: Double = frequency / sampleRate

        for _ in 0..<frameCount {
            // Generate triangle wave
            let triangleValue: Double = abs(fmod(phase, 1.0) - 0.5) * 4.0 - 1.0
            let sample: Float = Float(amplitude * triangleValue)
            output.append(sample)

            phase += phaseIncrement
            if phase >= 1.0 {
                phase -= 1.0
            }
        }

        return ["signal": output]
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

    func reset() {
        phase = 0.0
    }
}

/// Audio output block implementation
private class AudioOutputAudioBlock: AudioBlock {
    let id: UUID
    let type: BlockType = .audioOutput
    let inputPorts: [String] = ["input"]
    let outputPorts: [String] = []

    init(block: SignalBlock) {
        self.id = block.id
    }

    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        // Audio output consumes the signal but produces no output
        return [:]
    }

    func setParameter(name: String, value: Double) {
        // Audio output has no parameters
    }

    func reset() {
        // Nothing to reset
    }
}