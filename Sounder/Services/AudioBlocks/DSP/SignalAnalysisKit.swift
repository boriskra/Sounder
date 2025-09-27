import Foundation
import Darwin
import Accelerate

/// Signal analysis utilities for envelope following and FFT processing.
///
/// The kit provides timeline-coherent envelope followers, peak detection,
/// RMS analysis, and frequency domain transforms with atomic metrics tracking.
/// All operations are optimized for real-time use with lock-free monitoring
/// and thread-safe state management via spinlocks.
public final class SignalAnalysisKit {

    public enum AnalysisType: Int64 {
        case envelope = 0
        case rms = 1
        case peak = 2
        case spectral = 3
    }

    private struct EnvelopeState {
        var attackTime: Double = 0.001  // 1ms attack
        var releaseTime: Double = 0.100 // 100ms release
        var currentLevel: Double = 0.0
        var lastSample: UInt64 = 0
        var attackCoeff: Double = 0.0
        var releaseCoeff: Double = 0.0

        mutating func reset(sample: UInt64 = 0) {
            currentLevel = 0.0
            lastSample = sample
        }

        mutating func updateCoefficients(sampleRate: Double) {
            attackCoeff = exp(-1.0 / (attackTime * sampleRate))
            releaseCoeff = exp(-1.0 / (releaseTime * sampleRate))
        }
    }

    private struct SpectralState {
        var fftSize: Int = 1024
        var windowFunction: [Double] = []
        var inputBuffer: [Double] = []
        var outputBuffer: [Double] = []
        var fftSetup: FFTSetup?
        var lastSample: UInt64 = 0

        mutating func reset(sample: UInt64 = 0) {
            inputBuffer = Array(repeating: 0.0, count: fftSize)
            outputBuffer = Array(repeating: 0.0, count: fftSize)
            lastSample = sample
            generateWindow()
        }

        mutating func generateWindow() {
            windowFunction = Array(repeating: 0.0, count: fftSize)
            for i in 0..<fftSize {
                let phase = 2.0 * Double.pi * Double(i) / Double(fftSize - 1)
                windowFunction[i] = 0.5 * (1.0 - cos(phase)) // Hann window
            }
        }
    }

    private struct State {
        var envelope = EnvelopeState()
        var spectral = SpectralState()
        var lastAnalysisType: AnalysisType = .envelope
        var sampleRate: Double = 48000.0

        mutating func resetTimeline(sample: UInt64) {
            envelope.reset(sample: sample)
            spectral.reset(sample: sample)
        }
    }

    private var state = State()
    private var stateLock: Int32 = 0

    // Atomic performance counters
    private var envelopeSamplesRaw: Int64 = 0
    private var rmsSamplesRaw: Int64 = 0
    private var peakDetectionsRaw: Int64 = 0
    private var spectralAnalysesRaw: Int64 = 0
    private var timelineResetsRaw: Int64 = 0

    // Atomic analysis results
    private var lastEnvelopeBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var lastRMSBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var lastPeakBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var peakFrequencyBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var spectralCentroidBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var analysisTypeRaw: Int64 = AnalysisType.envelope.rawValue

    public init(fftSize: Int = 1024) {
        withLockedState { state in
            state.spectral.fftSize = fftSize
            state.spectral.reset()
            state.envelope.updateCoefficients(sampleRate: 48000.0)
        }
    }

    /// Performs envelope following with configurable attack/release times
    public func analyzeEnvelope(
        samples: [Double],
        startSample: UInt64,
        sampleRate: Double,
        attackTime: Double = 0.001,
        releaseTime: Double = 0.100
    ) -> [Double] {
        guard !samples.isEmpty else { return [] }

        var envelope = [Double](repeating: 0.0, count: samples.count)
        var finalLevel: Double = 0.0

        withLockedState { state in
            handleTimelineSync(startSample: startSample, state: &state)

            // Update envelope parameters if changed
            if abs(attackTime - state.envelope.attackTime) > 0.0001 ||
               abs(releaseTime - state.envelope.releaseTime) > 0.0001 ||
               abs(sampleRate - state.sampleRate) > 0.1 {
                state.envelope.attackTime = max(0.0001, attackTime)
                state.envelope.releaseTime = max(0.001, releaseTime)
                state.sampleRate = sampleRate
                state.envelope.updateCoefficients(sampleRate: sampleRate)
            }

            var level = state.envelope.currentLevel
            let attackCoeff = state.envelope.attackCoeff
            let releaseCoeff = state.envelope.releaseCoeff

            for (index, sample) in samples.enumerated() {
                let rectified = abs(sample)

                // Choose coefficient based on signal direction
                let coeff = rectified > level ? attackCoeff : releaseCoeff
                level = coeff * level + (1.0 - coeff) * rectified

                envelope[index] = level
            }

            state.envelope.currentLevel = level
            state.envelope.lastSample = startSample + UInt64(samples.count - 1)
            state.lastAnalysisType = .envelope
            finalLevel = level
        }

        // Update atomic metrics
        OSAtomicAdd64Barrier(Int64(samples.count), &envelopeSamplesRaw)
        withUnsafeMutablePointer(to: &lastEnvelopeBits) { atomicStoreDouble(finalLevel, $0) }
        withUnsafeMutablePointer(to: &analysisTypeRaw) { atomicStoreInt64(AnalysisType.envelope.rawValue, $0) }

        return envelope
    }

    /// Calculates RMS values with specified window size
    public func analyzeRMS(
        samples: [Double],
        startSample: UInt64,
        windowSize: Int = 512
    ) -> [Double] {
        guard !samples.isEmpty else { return [] }

        let effectiveWindowSize = min(max(windowSize, 64), samples.count)
        var rmsValues = [Double](repeating: 0.0, count: samples.count)
        var maxRMS: Double = 0.0

        // Calculate RMS using sliding window
        for i in 0..<samples.count {
            let windowStart = max(0, i - effectiveWindowSize / 2)
            let windowEnd = min(samples.count - 1, i + effectiveWindowSize / 2)

            var sumSquares: Double = 0.0
            var count: Int = 0

            for j in windowStart...windowEnd {
                sumSquares += samples[j] * samples[j]
                count += 1
            }

            let rms = sqrt(sumSquares / Double(count))
            rmsValues[i] = rms
            maxRMS = max(maxRMS, rms)
        }

        withLockedState { state in
            handleTimelineSync(startSample: startSample, state: &state)
            state.lastAnalysisType = .rms
        }

        // Update atomic metrics
        OSAtomicAdd64Barrier(Int64(samples.count), &rmsSamplesRaw)
        withUnsafeMutablePointer(to: &lastRMSBits) { atomicStoreDouble(maxRMS, $0) }
        withUnsafeMutablePointer(to: &analysisTypeRaw) { atomicStoreInt64(AnalysisType.rms.rawValue, $0) }

        return rmsValues
    }

    /// Detects peaks with specified threshold and minimum distance
    public func detectPeaks(
        samples: [Double],
        startSample: UInt64,
        threshold: Double = 0.1,
        minDistance: Int = 100
    ) -> [PeakInfo] {
        guard !samples.isEmpty else { return [] }

        var peaks: [PeakInfo] = []
        var lastPeakIndex = -minDistance

        for (index, sample) in samples.enumerated() {
            let amplitude = abs(sample)

            // Check if this is a peak
            if amplitude > threshold && (index - lastPeakIndex) >= minDistance {
                // Verify it's actually a local maximum
                let isLocalMax = checkLocalMaximum(samples: samples, index: index, radius: min(10, minDistance / 4))

                if isLocalMax {
                    peaks.append(PeakInfo(
                        sampleIndex: startSample + UInt64(index),
                        amplitude: amplitude,
                        value: sample
                    ))
                    lastPeakIndex = index
                }
            }
        }

        withLockedState { state in
            handleTimelineSync(startSample: startSample, state: &state)
            state.lastAnalysisType = .peak
        }

        let maxPeak = peaks.max(by: { $0.amplitude < $1.amplitude })?.amplitude ?? 0.0

        // Update atomic metrics
        OSAtomicAdd64Barrier(Int64(peaks.count), &peakDetectionsRaw)
        withUnsafeMutablePointer(to: &lastPeakBits) { atomicStoreDouble(maxPeak, $0) }
        withUnsafeMutablePointer(to: &analysisTypeRaw) { atomicStoreInt64(AnalysisType.peak.rawValue, $0) }

        return peaks
    }

    /// Performs FFT analysis and returns spectral information
    public func analyzeSpectrum(
        samples: [Double],
        startSample: UInt64,
        sampleRate: Double
    ) -> SpectralInfo? {
        guard !samples.isEmpty else { return nil }

        var spectralInfo: SpectralInfo?

        withLockedState { state in
            handleTimelineSync(startSample: startSample, state: &state)

            let fftSize = state.spectral.fftSize
            let windowedSamples = applyWindowAndPad(samples: samples, fftSize: fftSize, window: state.spectral.windowFunction)

            let (magnitudes, peakFreq, centroid) = performFFTAnalysis(samples: windowedSamples, sampleRate: sampleRate)

            spectralInfo = SpectralInfo(
                magnitudes: magnitudes,
                peakFrequency: peakFreq,
                spectralCentroid: centroid,
                fftSize: fftSize,
                sampleRate: sampleRate
            )

            state.lastAnalysisType = .spectral
        }

        // Update atomic metrics
        OSAtomicAdd64Barrier(1, &spectralAnalysesRaw)
        if let info = spectralInfo {
            withUnsafeMutablePointer(to: &peakFrequencyBits) { atomicStoreDouble(info.peakFrequency, $0) }
            withUnsafeMutablePointer(to: &spectralCentroidBits) { atomicStoreDouble(info.spectralCentroid, $0) }
        }
        withUnsafeMutablePointer(to: &analysisTypeRaw) { atomicStoreInt64(AnalysisType.spectral.rawValue, $0) }

        return spectralInfo
    }

    /// Resets analysis state to specified timeline position
    public func reset(to startSample: UInt64 = 0) {
        withLockedState { state in
            state.resetTimeline(sample: startSample)
        }
        OSAtomicAdd64Barrier(1, &timelineResetsRaw)
    }

    /// Returns current analysis metrics
    public func metrics() -> SignalAnalysisMetrics {
        let envelopeSamples = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &envelopeSamplesRaw))
        let rmsSamples = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &rmsSamplesRaw))
        let peakDetections = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &peakDetectionsRaw))
        let spectralAnalyses = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &spectralAnalysesRaw))
        let timelineResets = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &timelineResetsRaw))

        let envelope = withUnsafeMutablePointer(to: &lastEnvelopeBits, atomicLoadDouble)
        let rms = withUnsafeMutablePointer(to: &lastRMSBits, atomicLoadDouble)
        let peak = withUnsafeMutablePointer(to: &lastPeakBits, atomicLoadDouble)
        let peakFreq = withUnsafeMutablePointer(to: &peakFrequencyBits, atomicLoadDouble)
        let centroid = withUnsafeMutablePointer(to: &spectralCentroidBits, atomicLoadDouble)

        let typeRaw = OSAtomicAdd64Barrier(0, &analysisTypeRaw)
        let analysisType = AnalysisType(rawValue: typeRaw) ?? .envelope

        return SignalAnalysisMetrics(
            envelopeSamples: envelopeSamples,
            rmsSamples: rmsSamples,
            peakDetections: peakDetections,
            spectralAnalyses: spectralAnalyses,
            timelineResets: timelineResets,
            lastEnvelopeLevel: envelope,
            lastRMSLevel: rms,
            lastPeakLevel: peak,
            peakFrequency: peakFreq,
            spectralCentroid: centroid,
            lastAnalysisType: analysisType
        )
    }

    // MARK: - Private Implementation

    private func handleTimelineSync(startSample: UInt64, state: inout State) {
        if startSample < state.envelope.lastSample || startSample < state.spectral.lastSample {
            state.resetTimeline(sample: startSample)
            OSAtomicAdd64Barrier(1, &timelineResetsRaw)
        }
    }

    private func checkLocalMaximum(samples: [Double], index: Int, radius: Int) -> Bool {
        let centerValue = abs(samples[index])
        let startIndex = max(0, index - radius)
        let endIndex = min(samples.count - 1, index + radius)

        for i in startIndex...endIndex {
            if i != index && abs(samples[i]) > centerValue {
                return false
            }
        }
        return true
    }

    private func applyWindowAndPad(samples: [Double], fftSize: Int, window: [Double]) -> [Double] {
        var windowed = Array(repeating: 0.0, count: fftSize)
        let copyCount = min(samples.count, fftSize)

        for i in 0..<copyCount {
            windowed[i] = samples[i] * (i < window.count ? window[i] : 1.0)
        }

        return windowed
    }

    private func performFFTAnalysis(samples: [Double], sampleRate: Double) -> (magnitudes: [Double], peakFreq: Double, centroid: Double) {
        let fftSize = samples.count
        let log2Size = Int(log2(Double(fftSize)))

        // Simplified FFT using basic DFT for demonstration
        // In production, use vDSP_fft functions from Accelerate
        var magnitudes = [Double](repeating: 0.0, count: fftSize / 2)

        for k in 0..<(fftSize / 2) {
            var real: Double = 0.0
            var imag: Double = 0.0

            for n in 0..<fftSize {
                let angle = -2.0 * Double.pi * Double(k * n) / Double(fftSize)
                real += samples[n] * cos(angle)
                imag += samples[n] * sin(angle)
            }

            magnitudes[k] = sqrt(real * real + imag * imag) / Double(fftSize)
        }

        // Find peak frequency
        var peakIndex = 0
        var peakMagnitude: Double = 0.0
        for (index, magnitude) in magnitudes.enumerated() {
            if magnitude > peakMagnitude {
                peakMagnitude = magnitude
                peakIndex = index
            }
        }

        let peakFrequency = Double(peakIndex) * sampleRate / Double(fftSize)

        // Calculate spectral centroid
        var weightedSum: Double = 0.0
        var magnitudeSum: Double = 0.0

        for (index, magnitude) in magnitudes.enumerated() {
            let frequency = Double(index) * sampleRate / Double(fftSize)
            weightedSum += frequency * magnitude
            magnitudeSum += magnitude
        }

        let spectralCentroid = magnitudeSum > 0.0 ? weightedSum / magnitudeSum : 0.0

        return (magnitudes, peakFrequency, spectralCentroid)
    }

    @inline(__always)
    private func withLockedState<T>(_ body: (inout State) -> T) -> T {
        lockState()
        defer { unlockState() }
        return body(&state)
    }

    private func lockState() {
        while !OSAtomicCompareAndSwap32Barrier(0, 1, &stateLock) {
            sched_yield()
        }
    }

    private func unlockState() {
        while !OSAtomicCompareAndSwap32Barrier(1, 0, &stateLock) {
            sched_yield()
        }
    }
}

// MARK: - Data Structures

public struct PeakInfo: Sendable {
    public let sampleIndex: UInt64
    public let amplitude: Double
    public let value: Double
}

public struct SpectralInfo: Sendable {
    public let magnitudes: [Double]
    public let peakFrequency: Double
    public let spectralCentroid: Double
    public let fftSize: Int
    public let sampleRate: Double
}

public struct SignalAnalysisMetrics: Sendable {
    public let envelopeSamples: UInt64
    public let rmsSamples: UInt64
    public let peakDetections: UInt64
    public let spectralAnalyses: UInt64
    public let timelineResets: UInt64
    public let lastEnvelopeLevel: Double
    public let lastRMSLevel: Double
    public let lastPeakLevel: Double
    public let peakFrequency: Double
    public let spectralCentroid: Double
    public let lastAnalysisType: SignalAnalysisKit.AnalysisType
}

// MARK: - Atomic Helpers

@inline(__always)
private func atomicStoreDouble(_ value: Double, _ storage: UnsafeMutablePointer<Int64>) {
    var current = OSAtomicAdd64Barrier(0, storage)
    let newBits = Int64(bitPattern: value.bitPattern)
    while !OSAtomicCompareAndSwap64Barrier(current, newBits, storage) {
        current = OSAtomicAdd64Barrier(0, storage)
    }
}

@inline(__always)
private func atomicLoadDouble(_ storage: UnsafeMutablePointer<Int64>) -> Double {
    Double(bitPattern: UInt64(bitPattern: OSAtomicAdd64Barrier(0, storage)))
}

@inline(__always)
private func atomicStoreInt64(_ value: Int64, _ storage: UnsafeMutablePointer<Int64>) {
    var current = OSAtomicAdd64Barrier(0, storage)
    while !OSAtomicCompareAndSwap64Barrier(current, value, storage) {
        current = OSAtomicAdd64Barrier(0, storage)
    }
}

// MARK: - Factory Methods

extension SignalAnalysisKit {
    /// Creates an envelope follower optimized for percussive material
    public static func createPercussiveAnalyzer() -> SignalAnalysisKit {
        return SignalAnalysisKit(fftSize: 512)
    }

    /// Creates a spectral analyzer with high frequency resolution
    public static func createSpectralAnalyzer(fftSize: Int = 2048) -> SignalAnalysisKit {
        return SignalAnalysisKit(fftSize: fftSize)
    }

    /// Creates a general-purpose analyzer with balanced settings
    public static func createGeneralAnalyzer() -> SignalAnalysisKit {
        return SignalAnalysisKit(fftSize: 1024)
    }
}