import Foundation
import Darwin

/// Shared biquad filter implementation for all Sounder audio blocks.
///
/// The core provides lowpass, highpass, bandpass, and notch filtering with
/// timeline-coherent state management. Filter coefficients are computed
/// dynamically based on cutoff frequency, Q, and gain parameters. All state
/// transitions are protected by a spinlock for real-time thread safety,
/// while performance metrics are captured via atomic primitives.
public final class BiquadFilterCore {

    public enum FilterType: Int64 {
        case lowpass = 0
        case highpass = 1
        case bandpass = 2
        case notch = 3
        case peaking = 4
        case lowShelf = 5
        case highShelf = 6
    }

    private struct FilterState {
        var x1: Double = 0.0  // Input delay line
        var x2: Double = 0.0
        var y1: Double = 0.0  // Output delay line
        var y2: Double = 0.0
        var lastSample: UInt64 = 0

        mutating func reset(sample: UInt64 = 0) {
            x1 = 0.0
            x2 = 0.0
            y1 = 0.0
            y2 = 0.0
            lastSample = sample
        }
    }

    private struct Coefficients {
        var b0: Double = 1.0
        var b1: Double = 0.0
        var b2: Double = 0.0
        var a1: Double = 0.0
        var a2: Double = 0.0

        static let bypass = Coefficients(b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0)

        mutating func normalize() {
            let invA0 = 1.0 / max(abs(b0), 1.0e-15)
            b0 *= invA0
            b1 *= invA0
            b2 *= invA0
            a1 *= invA0
            a2 *= invA0
        }
    }

    private struct State {
        var filterState = FilterState()
        var coefficients = Coefficients.bypass
        var filterType: FilterType = .lowpass
        var frequency: Double = 1000.0
        var q: Double = 0.707
        var gain: Double = 0.0
        var sampleRate: Double = 48000.0
        var lastConfigUpdate: UInt64 = 0

        mutating func resetTimeline(sample: UInt64) {
            filterState.reset(sample: sample)
            lastConfigUpdate = sample
        }
    }

    private var state = State()
    private var stateLock: Int32 = 0

    // Atomic performance counters
    private var samplesProcessedRaw: Int64 = 0
    private var filterUpdatesRaw: Int64 = 0
    private var timelineResetsRaw: Int64 = 0
    private var stabilityViolationsRaw: Int64 = 0

    // Atomic parameter storage
    private var lastFrequencyBits: Int64 = Int64(bitPattern: Double(1000.0).bitPattern)
    private var lastQBits: Int64 = Int64(bitPattern: Double(0.707).bitPattern)
    private var lastGainBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var lastSampleRateBits: Int64 = Int64(bitPattern: Double(48000.0).bitPattern)
    private var peakOutputBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var filterTypeRaw: Int64 = FilterType.lowpass.rawValue

    public init() {
        updateCoefficients(type: .lowpass, frequency: 1000.0, q: 0.707, gain: 0.0, sampleRate: 48000.0)
    }

    /// Processes audio through the biquad filter with timeline coherence
    public func processAudio(
        samples: [Double],
        startSample: UInt64,
        sampleRate: Double,
        filterType: FilterType = .lowpass,
        frequency: Double = 1000.0,
        q: Double = 0.707,
        gain: Double = 0.0
    ) -> [Double] {
        guard !samples.isEmpty else { return [] }

        var output = [Double](repeating: 0.0, count: samples.count)
        var peak: Double = 0.0

        withLockedState { state in
            // Handle timeline discontinuities
            if startSample < state.filterState.lastSample {
                state.resetTimeline(sample: startSample)
                OSAtomicAdd64Barrier(1, &timelineResetsRaw)
            } else if startSample > state.filterState.lastSample + 1 {
                // Gap in timeline - maintain state but update position
                state.filterState.lastSample = startSample
            }

            // Update filter configuration if parameters changed
            let needsUpdate = abs(frequency - state.frequency) > 0.01 ||
                            abs(q - state.q) > 0.001 ||
                            abs(gain - state.gain) > 0.01 ||
                            abs(sampleRate - state.sampleRate) > 0.1 ||
                            filterType != state.filterType

            if needsUpdate {
                updateCoefficients(
                    type: filterType,
                    frequency: frequency,
                    q: q,
                    gain: gain,
                    sampleRate: sampleRate
                )
                state.coefficients = self.coefficients
                state.filterType = filterType
                state.frequency = frequency
                state.q = q
                state.gain = gain
                state.sampleRate = sampleRate
                state.lastConfigUpdate = startSample
                OSAtomicAdd64Barrier(1, &filterUpdatesRaw)
            }

            // Process samples through biquad filter
            let coeffs = state.coefficients
            var x1 = state.filterState.x1
            var x2 = state.filterState.x2
            var y1 = state.filterState.y1
            var y2 = state.filterState.y2

            for (index, sample) in samples.enumerated() {
                // Biquad difference equation: y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
                let x0 = sanitizeInput(sample)
                let y0 = coeffs.b0 * x0 + coeffs.b1 * x1 + coeffs.b2 * x2 - coeffs.a1 * y1 - coeffs.a2 * y2

                // Check for numerical stability
                let sanitizedOutput = sanitizeOutput(y0)
                if abs(sanitizedOutput - y0) > 1.0e-6 {
                    OSAtomicAdd64Barrier(1, &stabilityViolationsRaw)
                }

                output[index] = sanitizedOutput
                peak = max(peak, abs(sanitizedOutput))

                // Update delay lines
                x2 = x1
                x1 = x0
                y2 = y1
                y1 = sanitizedOutput
            }

            // Store updated state
            state.filterState.x1 = x1
            state.filterState.x2 = x2
            state.filterState.y1 = y1
            state.filterState.y2 = y2
            state.filterState.lastSample = startSample + UInt64(samples.count - 1)
        }

        // Update atomic metrics
        OSAtomicAdd64Barrier(Int64(samples.count), &samplesProcessedRaw)
        withUnsafeMutablePointer(to: &lastFrequencyBits) { atomicStoreDouble(frequency, $0) }
        withUnsafeMutablePointer(to: &lastQBits) { atomicStoreDouble(q, $0) }
        withUnsafeMutablePointer(to: &lastGainBits) { atomicStoreDouble(gain, $0) }
        withUnsafeMutablePointer(to: &lastSampleRateBits) { atomicStoreDouble(sampleRate, $0) }
        withUnsafeMutablePointer(to: &peakOutputBits) { atomicUpdateMaxDouble(peak, $0) }
        withUnsafeMutablePointer(to: &filterTypeRaw) { atomicStoreInt64(filterType.rawValue, $0) }

        return output
    }

    /// Resets filter state to specified timeline position
    public func reset(to startSample: UInt64 = 0) {
        withLockedState { state in
            state.resetTimeline(sample: startSample)
        }
        OSAtomicAdd64Barrier(1, &timelineResetsRaw)
    }

    /// Returns current performance metrics
    public func metrics() -> BiquadFilterMetrics {
        let samplesProcessed = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &samplesProcessedRaw))
        let filterUpdates = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &filterUpdatesRaw))
        let timelineResets = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &timelineResetsRaw))
        let stabilityViolations = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &stabilityViolationsRaw))

        let frequency = withUnsafeMutablePointer(to: &lastFrequencyBits, atomicLoadDouble)
        let q = withUnsafeMutablePointer(to: &lastQBits, atomicLoadDouble)
        let gain = withUnsafeMutablePointer(to: &lastGainBits, atomicLoadDouble)
        let sampleRate = withUnsafeMutablePointer(to: &lastSampleRateBits, atomicLoadDouble)
        let peakOutput = withUnsafeMutablePointer(to: &peakOutputBits, atomicLoadDouble)

        let typeRaw = OSAtomicAdd64Barrier(0, &filterTypeRaw)
        let filterType = FilterType(rawValue: typeRaw) ?? .lowpass

        return BiquadFilterMetrics(
            samplesProcessed: samplesProcessed,
            filterUpdates: filterUpdates,
            timelineResets: timelineResets,
            stabilityViolations: stabilityViolations,
            lastFrequency: frequency,
            lastQ: q,
            lastGain: gain,
            lastSampleRate: sampleRate,
            peakOutput: peakOutput,
            filterType: filterType
        )
    }

    // MARK: - Private Implementation

    private var coefficients = Coefficients.bypass

    private func updateCoefficients(
        type: FilterType,
        frequency: Double,
        q: Double,
        gain: Double,
        sampleRate: Double
    ) {
        let nyquist = sampleRate * 0.5
        let clampedFreq = max(1.0, min(frequency, nyquist * 0.99))
        let clampedQ = max(0.1, min(q, 100.0))
        let clampedGain = max(-60.0, min(gain, 60.0))

        let omega = 2.0 * Double.pi * clampedFreq / sampleRate
        let cosOmega = cos(omega)
        let sinOmega = sin(omega)
        let alpha = sinOmega / (2.0 * clampedQ)
        let A = pow(10.0, clampedGain / 40.0)  // For shelving filters

        switch type {
        case .lowpass:
            coefficients.b0 = (1.0 - cosOmega) * 0.5
            coefficients.b1 = 1.0 - cosOmega
            coefficients.b2 = (1.0 - cosOmega) * 0.5
            coefficients.a1 = -2.0 * cosOmega
            coefficients.a2 = 1.0 - alpha

        case .highpass:
            coefficients.b0 = (1.0 + cosOmega) * 0.5
            coefficients.b1 = -(1.0 + cosOmega)
            coefficients.b2 = (1.0 + cosOmega) * 0.5
            coefficients.a1 = -2.0 * cosOmega
            coefficients.a2 = 1.0 - alpha

        case .bandpass:
            coefficients.b0 = alpha
            coefficients.b1 = 0.0
            coefficients.b2 = -alpha
            coefficients.a1 = -2.0 * cosOmega
            coefficients.a2 = 1.0 - alpha

        case .notch:
            coefficients.b0 = 1.0
            coefficients.b1 = -2.0 * cosOmega
            coefficients.b2 = 1.0
            coefficients.a1 = -2.0 * cosOmega
            coefficients.a2 = 1.0 - alpha

        case .peaking:
            coefficients.b0 = 1.0 + alpha * A
            coefficients.b1 = -2.0 * cosOmega
            coefficients.b2 = 1.0 - alpha * A
            coefficients.a1 = -2.0 * cosOmega
            coefficients.a2 = 1.0 - alpha / A

        case .lowShelf:
            let S = 1.0
            let beta = sqrt(A) / clampedQ
            coefficients.b0 = A * ((A + 1.0) - (A - 1.0) * cosOmega + beta * sinOmega)
            coefficients.b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosOmega)
            coefficients.b2 = A * ((A + 1.0) - (A - 1.0) * cosOmega - beta * sinOmega)
            coefficients.a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosOmega)
            coefficients.a2 = (A + 1.0) + (A - 1.0) * cosOmega - beta * sinOmega

        case .highShelf:
            let S = 1.0
            let beta = sqrt(A) / clampedQ
            coefficients.b0 = A * ((A + 1.0) + (A - 1.0) * cosOmega + beta * sinOmega)
            coefficients.b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosOmega)
            coefficients.b2 = A * ((A + 1.0) + (A - 1.0) * cosOmega - beta * sinOmega)
            coefficients.a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosOmega)
            coefficients.a2 = (A + 1.0) - (A - 1.0) * cosOmega - beta * sinOmega
        }

        // Normalize coefficients (assuming a0 = 1 + alpha for most cases)
        let a0 = 1.0 + alpha
        coefficients.b0 /= a0
        coefficients.b1 /= a0
        coefficients.b2 /= a0
        coefficients.a1 /= a0
        coefficients.a2 /= a0
    }

    @inline(__always)
    private func sanitizeInput(_ input: Double) -> Double {
        guard input.isFinite else { return 0.0 }
        return max(-100.0, min(100.0, input))
    }

    @inline(__always)
    private func sanitizeOutput(_ output: Double) -> Double {
        guard output.isFinite else { return 0.0 }
        return max(-100.0, min(100.0, output))
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

// MARK: - Metrics Structure

public struct BiquadFilterMetrics: Sendable {
    public let samplesProcessed: UInt64
    public let filterUpdates: UInt64
    public let timelineResets: UInt64
    public let stabilityViolations: UInt64
    public let lastFrequency: Double
    public let lastQ: Double
    public let lastGain: Double
    public let lastSampleRate: Double
    public let peakOutput: Double
    public let filterType: BiquadFilterCore.FilterType
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
private func atomicUpdateMaxDouble(_ value: Double, _ storage: UnsafeMutablePointer<Int64>) {
    var current = OSAtomicAdd64Barrier(0, storage)
    while true {
        let currentValue = Double(bitPattern: UInt64(bitPattern: current))
        if value <= currentValue {
            return
        }

        let newBits = Int64(bitPattern: value.bitPattern)
        if OSAtomicCompareAndSwap64Barrier(current, newBits, storage) {
            return
        }

        current = OSAtomicAdd64Barrier(0, storage)
    }
}

@inline(__always)
private func atomicStoreInt64(_ value: Int64, _ storage: UnsafeMutablePointer<Int64>) {
    var current = OSAtomicAdd64Barrier(0, storage)
    while !OSAtomicCompareAndSwap64Barrier(current, value, storage) {
        current = OSAtomicAdd64Barrier(0, storage)
    }
}

// MARK: - Factory Methods

extension BiquadFilterCore {
    /// Creates a lowpass filter with specified cutoff and Q
    public static func createLowpass(frequency: Double, q: Double = 0.707) -> BiquadFilterCore {
        let filter = BiquadFilterCore()
        filter.updateCoefficients(type: .lowpass, frequency: frequency, q: q, gain: 0.0, sampleRate: 48000.0)
        return filter
    }

    /// Creates a highpass filter with specified cutoff and Q
    public static func createHighpass(frequency: Double, q: Double = 0.707) -> BiquadFilterCore {
        let filter = BiquadFilterCore()
        filter.updateCoefficients(type: .highpass, frequency: frequency, q: q, gain: 0.0, sampleRate: 48000.0)
        return filter
    }

    /// Creates a bandpass filter with specified center frequency and Q
    public static func createBandpass(frequency: Double, q: Double = 1.0) -> BiquadFilterCore {
        let filter = BiquadFilterCore()
        filter.updateCoefficients(type: .bandpass, frequency: frequency, q: q, gain: 0.0, sampleRate: 48000.0)
        return filter
    }
}