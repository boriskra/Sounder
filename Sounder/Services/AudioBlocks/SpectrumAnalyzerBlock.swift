import Foundation
import Accelerate

/// Real-time spectrum analyzer with FFT-based frequency analysis
/// Provides magnitude and phase information for audio visualization
public class SpectrumAnalyzerBlock: AudioBlock {
    public let id: UUID
    public let type: BlockType = .spectrumAnalyzer
    public let inputPorts: [String] = ["input"]
    public let outputPorts: [String] = ["magnitude", "phase"]

    // FFT configuration
    private var _windowSize: Int = 1024
    private var _overlap: Double = 50.0 // Percentage
    private var _windowType: WindowType = .hanning

    // FFT processing
    private var fftSetup: FFTSetup?
    private var inputBuffer: [Float] = []
    private var windowFunction: [Float] = []
    private var realBuffer: [Float] = []
    private var imagBuffer: [Float] = []
    private var magnitudeSpectrum: [Float] = []
    private var phaseSpectrum: [Float] = []
    private var log2n: vDSP_Length = 0

    // Overlap processing
    private var overlapBuffer: [Float] = []
    private var hopSize: Int = 512
    private var framesSinceLastFFT: Int = 0

    // Analysis parameters
    private let sampleRate: Double
    private var frequencyResolution: Double = 0.0
    private var analysisGain: Double = 1.0

    // Performance monitoring
    private var sampleCount: UInt64 = 0
    private var fftCount: UInt64 = 0
    private var peakFrequency: Double = 0.0
    private var spectralCentroid: Double = 0.0

    public var windowSize: Int { _windowSize }

    public init(signalBlock: SignalBlock, sampleRate: Double = 48000.0) {
        self.id = signalBlock.id
        self.sampleRate = sampleRate

        // Initialize from block parameters
        if let windowParam = signalBlock.parameters["windowSize"] {
            _windowSize = Int(windowParam.value)
        }

        if let overlapParam = signalBlock.parameters["overlap"] {
            _overlap = overlapParam.value
        }

        setupFFT()
        calculateFrequencyResolution()
    }

    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    // MARK: - AudioBlock Protocol

    public func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        return processAudio(inputs: inputs, frameCount: frameCount)
    }

    public func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        guard let audioInput = inputs["input"], audioInput.count >= frameCount else {
            // Return empty analysis if no input
            return [
                "magnitude": Array(repeating: 0.0, count: _windowSize / 2),
                "phase": Array(repeating: 0.0, count: _windowSize / 2)
            ]
        }

        // Add new samples to input buffer
        inputBuffer.append(contentsOf: audioInput[0..<frameCount])
        framesSinceLastFFT += frameCount
        sampleCount += UInt64(frameCount)

        // Check if we have enough samples for FFT
        if framesSinceLastFFT >= hopSize && inputBuffer.count >= _windowSize {
            performFFTAnalysis()
            framesSinceLastFFT = 0
            fftCount += 1
        }

        // Return current spectrum data
        return [
            "magnitude": magnitudeSpectrum,
            "phase": phaseSpectrum
        ]
    }

    public func setParameter(name: String, value: Double) {
        switch name {
        case "windowSize":
            let newSize: Int = Int(pow(2.0, round(log2(value)))) // Ensure power of 2
            if newSize != _windowSize && newSize >= 256 && newSize <= 8192 {
                _windowSize = newSize
                setupFFT()
                calculateFrequencyResolution()
            }

        case "overlap":
            _overlap = max(0.0, min(75.0, value))
            hopSize = Int(Double(_windowSize) * (1.0 - _overlap / 100.0))

        case "gain":
            analysisGain = pow(10.0, value / 20.0) // Convert dB to linear

        default:
            break
        }
    }

    public func reset(to startSample: UInt64, sampleRate: Double) {
        reset()
        print("📊 [DEBUG] SpectrumAnalyzerBlock.reset(to:) - Reset to sample \(startSample) at \(sampleRate)Hz")
    }

    public func reset() {
        inputBuffer.removeAll()
        overlapBuffer.removeAll()
        framesSinceLastFFT = 0
        sampleCount = 0
        fftCount = 0

        // Clear spectrum data
        magnitudeSpectrum = Array(repeating: 0.0, count: _windowSize / 2)
        phaseSpectrum = Array(repeating: 0.0, count: _windowSize / 2)
    }

    // MARK: - FFT Setup and Processing

    /// Sets up FFT processing
    private func setupFFT() {
        // Clean up existing setup
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }

        // Calculate log2 of window size
        log2n = vDSP_Length(log2(Float(_windowSize)))

        // Create new FFT setup
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

        // Initialize buffers
        inputBuffer.reserveCapacity(_windowSize * 2)
        realBuffer = Array(repeating: 0.0, count: _windowSize / 2)
        imagBuffer = Array(repeating: 0.0, count: _windowSize / 2)
        magnitudeSpectrum = Array(repeating: 0.0, count: _windowSize / 2)
        phaseSpectrum = Array(repeating: 0.0, count: _windowSize / 2)

        // Setup overlap processing
        hopSize = Int(Double(_windowSize) * (1.0 - _overlap / 100.0))
        overlapBuffer = Array(repeating: 0.0, count: _windowSize)

        // Generate window function
        generateWindowFunction()
    }

    /// Generates the window function for FFT
    private func generateWindowFunction() {
        windowFunction = Array(repeating: 0.0, count: _windowSize)

        switch _windowType {
        case .hanning:
            vDSP_hann_window(&windowFunction, vDSP_Length(_windowSize), Int32(vDSP_HANN_NORM))

        case .hamming:
            vDSP_hamm_window(&windowFunction, vDSP_Length(_windowSize), 0)

        case .blackman:
            vDSP_blkman_window(&windowFunction, vDSP_Length(_windowSize), 0)

        case .rectangular:
            windowFunction = Array(repeating: 1.0, count: _windowSize)
        }
    }

    /// Performs FFT analysis on current input buffer
    private func performFFTAnalysis() {
        guard let setup = fftSetup, inputBuffer.count >= _windowSize else { return }

        // Extract window of samples
        let windowStart: Int = inputBuffer.count - _windowSize
        var windowedSamples: [Float] = Array(inputBuffer[windowStart..<inputBuffer.count])

        // Apply window function
        vDSP_vmul(windowedSamples, 1, windowFunction, 1, &windowedSamples, 1, vDSP_Length(_windowSize))

        // Apply analysis gain
        if analysisGain != 1.0 {
            vDSP_vsmul(windowedSamples, 1, [Float(analysisGain)], &windowedSamples, 1, vDSP_Length(_windowSize))
        }

        // Prepare input array in packed complex format
        var packedReal: [Float] = Array(repeating: Float(0), count: _windowSize / 2)
        var packedImag: [Float] = Array(repeating: Float(0), count: _windowSize / 2)

        // Pack real input into complex format
        for index in 0..<(_windowSize / 2) {
            packedReal[index] = windowedSamples[index * 2]
            if index * 2 + 1 < _windowSize {
                packedImag[index] = windowedSamples[index * 2 + 1]
            }
        }

        guard let setup = fftSetup else { return }

        // Perform FFT with safe pointer access
        packedReal.withUnsafeMutableBufferPointer { realPtr in
            packedImag.withUnsafeMutableBufferPointer { imagPtr in
                guard let realBase = realPtr.baseAddress, let imagBase = imagPtr.baseAddress else { return }
                var splitComplex: DSPSplitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)
                vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }

        // Copy results to output buffers
        realBuffer = packedReal
        imagBuffer = packedImag

        // Calculate magnitude and phase spectra
        calculateSpectra()

        // Update analysis statistics
        updateAnalysisStatistics()

        // Remove processed samples (with overlap)
        let samplesToRemove: Int = hopSize
        if inputBuffer.count > samplesToRemove {
            inputBuffer.removeFirst(samplesToRemove)
        }
    }

    /// Calculates magnitude and phase spectra from FFT output
    private func calculateSpectra() {
        let numBins: Int = _windowSize / 2

        for index in 0..<numBins {
            let real: Float = realBuffer[index]
            let imag: Float = imagBuffer[index]

            // Calculate magnitude
            let magnitude: Float = sqrt(real * real + imag * imag)
            magnitudeSpectrum[index] = magnitude

            // Calculate phase
            let phase: Float = atan2(imag, real)
            phaseSpectrum[index] = phase
        }

        // Normalize magnitude spectrum
        let scaleFactor: Float = 2.0 / Float(_windowSize)
        vDSP_vsmul(magnitudeSpectrum, 1, [scaleFactor], &magnitudeSpectrum, 1, vDSP_Length(numBins))
    }

    /// Updates analysis statistics
    private func updateAnalysisStatistics() {
        // Find peak frequency
        var maxIndex: vDSP_Length = 0
        var maxValue: Float = 0.0
        vDSP_maxvi(magnitudeSpectrum, 1, &maxValue, &maxIndex, vDSP_Length(magnitudeSpectrum.count))
        peakFrequency = Double(maxIndex) * frequencyResolution

        // Calculate spectral centroid
        spectralCentroid = calculateSpectralCentroid()
    }

    /// Calculates frequency resolution
    private func calculateFrequencyResolution() {
        frequencyResolution = sampleRate / Double(_windowSize)
    }

    // MARK: - Spectral Analysis

    /// Calculates spectral centroid (brightness measure)
    private func calculateSpectralCentroid() -> Double {
        var weightedSum: Double = 0.0
        var magnitudeSum: Double = 0.0

        for index in 0..<magnitudeSpectrum.count {
            let frequency: Double = Double(index) * frequencyResolution
            let magnitude: Double = Double(magnitudeSpectrum[index])

            weightedSum += frequency * magnitude
            magnitudeSum += magnitude
        }

        return magnitudeSum > 0 ? weightedSum / magnitudeSum : 0.0
    }

    /// Gets spectrum data for a specific frequency range
    public func getSpectrumInRange(minFreq: Double, maxFreq: Double) -> [Float] {
        let startBin: Int = Int(minFreq / frequencyResolution)
        let endBin: Int = Int(maxFreq / frequencyResolution)

        let clampedStart: Int = max(0, startBin)
        let clampedEnd: Int = min(magnitudeSpectrum.count - 1, endBin)

        guard clampedStart <= clampedEnd else { return [] }

        return Array(magnitudeSpectrum[clampedStart...clampedEnd])
    }

    /// Finds peaks in the spectrum
    public func findSpectralPeaks(threshold: Float = 0.1, minSeparation: Double = 100.0) -> [SpectralPeak] {
        var peaks: [SpectralPeak] = []
        _ = Int(minSeparation / frequencyResolution) // Could be used for bin-based separation if needed

        for index in 1..<(magnitudeSpectrum.count - 1) {
            let current: Float = magnitudeSpectrum[index]
            let prev: Float = magnitudeSpectrum[index - 1]
            let next: Float = magnitudeSpectrum[index + 1]

            // Check if this is a local maximum above threshold
            if current > prev && current > next && current > threshold {
                // Check minimum separation from existing peaks
                let frequency: Double = Double(index) * frequencyResolution
                let tooClose: Bool = peaks.contains { abs($0.frequency - frequency) < minSeparation }

                if !tooClose {
                    peaks.append(SpectralPeak(
                        frequency: frequency,
                        magnitude: current,
                        binIndex: index
                    ))
                }
            }
        }

        // Sort by magnitude (strongest peaks first)
        return peaks.sorted { $0.magnitude > $1.magnitude }
    }

    // MARK: - Performance Analysis

    /// Gets performance and analysis statistics
    public func getAnalysisStats() -> SpectrumAnalyzerStats {
        return SpectrumAnalyzerStats(
            samplesProcessed: sampleCount,
            fftCount: fftCount,
            windowSize: _windowSize,
            overlap: _overlap,
            frequencyResolution: frequencyResolution,
            peakFrequency: peakFrequency,
            spectralCentroid: spectralCentroid,
            analysisLatency: calculateAnalysisLatency()
        )
    }

    /// Calculates analysis latency
    private func calculateAnalysisLatency() -> Double {
        // Latency = window size + overlap buffer
        let windowLatency: Double = Double(_windowSize) / sampleRate
        let overlapLatency: Double = Double(hopSize) / sampleRate
        return (windowLatency + overlapLatency) * 1000.0 // Convert to milliseconds
    }

    /// Gets current spectrum analysis quality
    public func getAnalysisQuality() -> AnalysisQuality {
        let noiseFloor: Double = calculateNoiseFloor()
        let dynamicRange: Double = calculateDynamicRange()
        let frequencyAccuracy: Double = calculateFrequencyAccuracy()

        return AnalysisQuality(
            noiseFloor: noiseFloor,
            dynamicRange: dynamicRange,
            frequencyAccuracy: frequencyAccuracy,
            windowEfficiency: calculateWindowEfficiency(),
            overallQuality: (dynamicRange + frequencyAccuracy + calculateWindowEfficiency()) / 3.0
        )
    }

    /// Calculates noise floor of the analysis
    private func calculateNoiseFloor() -> Double {
        // Find minimum magnitude (excluding DC bin)
        let nonDcSpectrum: [Float] = Array(magnitudeSpectrum[1...])
        let minMagnitude: Float = nonDcSpectrum.min() ?? 0.0
        return Double(minMagnitude)
    }

    /// Calculates dynamic range of the analysis
    private func calculateDynamicRange() -> Double {
        let maxMagnitude: Float = magnitudeSpectrum.max() ?? 0.0
        let minMagnitude: Float = magnitudeSpectrum.min() ?? 0.000001
        return 20.0 * log10(Double(maxMagnitude) / Double(minMagnitude))
    }

    /// Calculates frequency accuracy based on window size
    private func calculateFrequencyAccuracy() -> Double {
        // Accuracy improves with larger window sizes
        let accuracy: Double = frequencyResolution / 1000.0 // Normalize to 1kHz
        return min(1.0, 1.0 / accuracy) // Higher is better
    }

    /// Calculates window function efficiency
    private func calculateWindowEfficiency() -> Double {
        switch _windowType {
        case .hanning: return 0.9
        case .hamming: return 0.85
        case .blackman: return 0.95
        case .rectangular: return 0.7
        }
    }
}

// MARK: - Data Structures

/// Window function types for FFT analysis
public enum WindowType: String, CaseIterable {
    /// Hanning window (good balance of resolution and leakage)
    case hanning
    /// Hamming window (similar to Hanning with different coefficients)
    case hamming
    /// Blackman window (low leakage, reduced resolution)
    case blackman
    /// Rectangular window (no windowing, highest leakage)
    case rectangular
}

/// Represents a peak in the frequency spectrum
public struct SpectralPeak {
    /// Frequency of the peak in Hz
    public let frequency: Double
    /// Magnitude of the peak
    public let magnitude: Float
    /// Index of the frequency bin
    public let binIndex: Int
}

/// Statistics and performance metrics for spectrum analysis
public struct SpectrumAnalyzerStats {
    /// Total number of audio samples processed
    public let samplesProcessed: UInt64
    /// Number of FFT computations performed
    public let fftCount: UInt64
    /// Current FFT window size
    public let windowSize: Int
    /// Window overlap percentage
    public let overlap: Double
    /// Frequency resolution in Hz per bin
    public let frequencyResolution: Double
    /// Frequency of the strongest spectral peak
    public let peakFrequency: Double
    /// Spectral centroid (brightness measure)
    public let spectralCentroid: Double
    /// Analysis latency in milliseconds
    public let analysisLatency: Double
}

/// Quality metrics for spectrum analysis
public struct AnalysisQuality {
    /// Noise floor level
    public let noiseFloor: Double
    /// Dynamic range in dB
    public let dynamicRange: Double
    /// Frequency accuracy metric
    public let frequencyAccuracy: Double
    /// Window function efficiency
    public let windowEfficiency: Double
    /// Overall quality score
    public let overallQuality: Double
}

// MARK: - Factory Methods

extension SpectrumAnalyzerBlock {
    /// Creates a high-resolution spectrum analyzer
    public static func createHighResolution() -> SpectrumAnalyzerBlock {
        let signalBlock: SignalBlock = SignalBlock(
            type: .spectrumAnalyzer,
            title: "High-Res Analyzer",
            position: CGPoint.zero,
            parameters: [
                "windowSize": BlockParameter(
                    name: "windowSize",
                    displayName: "Window Size",
                    value: 4096,
                    minimumValue: 512,
                    maximumValue: 8192,
                    unit: "samples",
                    stepSize: 1
                ),
                "overlap": BlockParameter.percentage(
                    name: "overlap",
                    displayName: "Overlap",
                    value: 75.0
                )
            ],
            inputPorts: BlockType.spectrumAnalyzer.defaultInputPorts,
            outputPorts: BlockType.spectrumAnalyzer.defaultOutputPorts
        )

        return SpectrumAnalyzerBlock(signalBlock: signalBlock)
    }
}
