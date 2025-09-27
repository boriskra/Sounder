import Foundation
import Darwin

/// Shared gain staging and parameter smoothing utility across audio blocks.
///
/// The helper maintains timeline-coherent automation ramps, offers precise
/// dB/linear conversions, and applies soft-clipped gain adjustments without
/// introducing zipper noise. All observable metrics are captured with atomic
/// primitives so render threads can operate lock-free while developer tooling
/// inspects performance from background queues.
public final class GainAndSmoothing {
    // MARK: - Internal State

    private struct RampState {
        var startValue: Double = 0.0
        var endValue: Double = 0.0
        var startSample: UInt64 = 0
        var endSample: UInt64 = 0
        var sampleRate: Double = 0.0
    }

    private struct GainState {
        var gainLinear: Double = 1.0
        var startSample: UInt64 = 0
        var endSample: UInt64 = 0
        var sampleRate: Double = 0.0
    }

    private var rampState = RampState()
    private var gainState = GainState()

    // MARK: - Atomic Performance Counters

    private var rampInvocationCountRaw: Int64 = 0
    private var gainInvocationCountRaw: Int64 = 0
    private var totalSamplesProcessedRaw: Int64 = 0
    private var clippedSamplesRaw: Int64 = 0

    private var lastRampLengthRaw: Int64 = 0
    private var lastRampStartSampleBits: Int64 = 0
    private var lastRampEndSampleBits: Int64 = 0
    private var lastGainStartSampleBits: Int64 = 0
    private var lastGainEndSampleBits: Int64 = 0

    private var lastParameterStartBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var lastParameterEndBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var peakParameterDeltaBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var lastGainDbBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var lastGainLinearBits: Int64 = Int64(bitPattern: Double(1.0).bitPattern)
    private var peakGainLinearBits: Int64 = Int64(bitPattern: Double(1.0).bitPattern)
    private var lastOutputRmsBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)

    #if DEBUG
    private var rampComputationTimeRaw: Int64 = 0
    private var gainComputationTimeRaw: Int64 = 0
    private var rampTimingInvocationCountRaw: Int64 = 0
    private var gainTimingInvocationCountRaw: Int64 = 0
    #endif

    public init() {}

    // MARK: - Parameter Smoothing

    /// Generates a Hermite-smoothed parameter ramp coherent with the absolute
    /// timeline. The ramp restarts automatically when a transport jump is
    /// detected to avoid discontinuities that would cause zipper noise.
    /// - Parameters:
    ///   - startValue: First value for the ramp segment.
    ///   - endValue: Target value after `rampSamples` samples.
    ///   - rampSamples: Number of samples that span the ramp. Values ≤ 0 coerce
    ///     to a single-sample update.
    ///   - startSample: Absolute timeline sample index represented by the first
    ///     ramp sample.
    ///   - sampleRate: Rendering sample rate in Hertz, used for validation and
    ///     metrics correlation.
    /// - Returns: Array of ramped values suitable for per-sample application.
    public func smoothParameter(
        from startValue: Double,
        to endValue: Double,
        rampSamples: Int,
        startSample: UInt64 = 0,
        sampleRate: Double = 48_000.0
    ) -> [Double] {
        var storage = Array(repeating: 0.0, count: max(1, rampSamples))
        smoothParameter(
            from: startValue,
            to: endValue,
            rampSamples: rampSamples,
            startSample: startSample,
            sampleRate: sampleRate,
            into: &storage
        )
        return storage
    }

    /// Timeline-aware parameter smoothing that writes the ramp into the
    /// provided storage to avoid intermediate allocations on the audio thread.
    /// - Parameters mirror `smoothParameter(from:to:rampSamples:startSample:sampleRate:)`.
    public func smoothParameter(
        from startValue: Double,
        to endValue: Double,
        rampSamples: Int,
        startSample: UInt64,
        sampleRate: Double,
        into storage: inout [Double]
    ) {
        let count = max(1, rampSamples)
        precondition(sampleRate > 0, "Sample rate must be positive for parameter smoothing")

        storage.removeAll(keepingCapacity: true)
        storage.reserveCapacity(count)

        #if DEBUG
        let timingStart = DispatchTime.now().uptimeNanoseconds
        #endif

        let transportJumped = startSample < rampState.startSample
        if transportJumped {
            rampState = RampState(
                startValue: startValue,
                endValue: startValue,
                startSample: startSample,
                endSample: startSample,
                sampleRate: sampleRate
            )
        }

        let effectiveStart: Double
        if !transportJumped && startSample >= rampState.startSample && startSample <= rampState.endSample {
            // Continuation within the previous segment; interpolate from stored state.
            let span = max(1, Int(rampState.endSample &- rampState.startSample))
            let offset = Int(startSample &- rampState.startSample)
            let position = Double(offset) / Double(span)
            let easedPosition = smoothstep(position)
            effectiveStart = hermiteInterpolation(
                t: easedPosition,
                start: rampState.startValue,
                end: rampState.endValue
            )
        } else if !transportJumped && startSample == rampState.endSample {
            // Perfectly contiguous block; reuse prior end value.
            effectiveStart = rampState.endValue
        } else {
            effectiveStart = startValue
        }

        if count == 1 {
            storage.append(endValue)
        } else {
            let inverseCount = 1.0 / Double(count - 1)
            let delta = endValue - effectiveStart
            for index in 0..<count {
                let progress = Double(index) * inverseCount
                let eased = smoothstep(progress)
                storage.append(fma(delta, eased, effectiveStart))
            }
            storage[count - 1] = endValue
        }

        rampState = RampState(
            startValue: storage.first ?? endValue,
            endValue: endValue,
            startSample: startSample,
            endSample: startSample &+ UInt64(count - 1),
            sampleRate: sampleRate
        )

        updateRampMetrics(
            startValue: storage.first ?? endValue,
            endValue: endValue,
            rampSamples: count,
            startSample: startSample,
            endSample: rampState.endSample
        )

        #if DEBUG
        let elapsed = DispatchTime.now().uptimeNanoseconds &- timingStart
        OSAtomicAdd64Barrier(Int64(bitPattern: elapsed), &rampComputationTimeRaw)
        OSAtomicAdd64Barrier(1, &rampTimingInvocationCountRaw)
        #endif
    }

    /// Interpolates a value at an arbitrary timeline sample using the most
    /// recent ramp segment. If the requested sample lies outside the stored
    /// segment the nearest endpoint is returned.
    public func interpolatedValue(at sample: UInt64) -> Double {
        if sample <= rampState.startSample {
            return rampState.startValue
        }
        if sample >= rampState.endSample {
            return rampState.endValue
        }
        let span = max(1, Int(rampState.endSample &- rampState.startSample))
        let offset = Int(sample &- rampState.startSample)
        let position = Double(offset) / Double(span)
        let eased = smoothstep(position)
        return hermiteInterpolation(t: eased, start: rampState.startValue, end: rampState.endValue)
    }

    // MARK: - Gain Application

    /// Applies a decibel gain curve to the provided samples with soft-clipping
    /// protection to suppress inter-sample peaks. All state updates are
    /// timeline-aware, enabling deterministic render passes when bouncing or
    /// scrubbing.
    /// - Parameters:
    ///   - samples: Input mono buffer.
    ///   - gainDB: Gain amount expressed in decibels.
    ///   - startSample: Absolute timeline sample covered by `samples.first`.
    ///   - sampleRate: Rendering sample rate in Hertz.
    /// - Returns: Copy of the input buffer with gain and soft clipping applied.
    public func applyGain(
        samples: [Float],
        gainDB: Double,
        startSample: UInt64 = 0,
        sampleRate: Double = 48_000.0
    ) -> [Float] {
        guard !samples.isEmpty else { return samples }
        precondition(sampleRate > 0, "Sample rate must be positive for gain application")

        #if DEBUG
        let timingStart = DispatchTime.now().uptimeNanoseconds
        #endif

        let sanitizedGainDB = gainDB.isFinite ? gainDB : withUnsafeMutablePointer(to: &lastGainDbBits, atomicLoadDouble)
        let linearGain = dbToLinear(sanitizedGainDB)

        var output = samples
        var localClipped: UInt64 = 0
        var sumSquares = 0.0

        output.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let count = buffer.count
            for index in 0..<count {
                let scaled = Float(linearGain) * baseAddress[index]
                let clipped = softClip(scaled)
                if clipped.clipped {
                    localClipped &+= 1
                }
                let value = clipped.sample
                baseAddress[index] = value
                sumSquares = fma(Double(value), Double(value), sumSquares)
            }
        }

        let rms = sqrt(sumSquares / Double(output.count))

        if startSample < gainState.startSample {
            gainState = GainState(gainLinear: linearGain, startSample: startSample, endSample: startSample &+ UInt64(output.count - 1), sampleRate: sampleRate)
        } else {
            gainState.gainLinear = linearGain
            gainState.startSample = startSample
            gainState.endSample = startSample &+ UInt64(output.count - 1)
            gainState.sampleRate = sampleRate
        }

        updateGainMetrics(
            gainDB: sanitizedGainDB,
            gainLinear: linearGain,
            startSample: startSample,
            endSample: gainState.endSample,
            rms: rms,
            clippedSamples: localClipped,
            processedSamples: output.count
        )

        #if DEBUG
        let elapsed = DispatchTime.now().uptimeNanoseconds &- timingStart
        OSAtomicAdd64Barrier(Int64(bitPattern: elapsed), &gainComputationTimeRaw)
        OSAtomicAdd64Barrier(1, &gainTimingInvocationCountRaw)
        #endif

        return output
    }

    // MARK: - Metrics

    /// Captures a lock-free snapshot of the latest signal conditioning metrics.
    public func metrics() -> GainSmoothingMetrics {
        let ramps = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &rampInvocationCountRaw))
        let gainOperations = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &gainInvocationCountRaw))
        let processed = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &totalSamplesProcessedRaw))
        let clipped = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &clippedSamplesRaw))

        let lastRampLength = Int(atomicLoadInt64(&lastRampLengthRaw))
        let rampStart = withUnsafeMutablePointer(to: &lastRampStartSampleBits, atomicLoadUInt64)
        let rampEnd = withUnsafeMutablePointer(to: &lastRampEndSampleBits, atomicLoadUInt64)
        let gainStart = withUnsafeMutablePointer(to: &lastGainStartSampleBits, atomicLoadUInt64)
        let gainEnd = withUnsafeMutablePointer(to: &lastGainEndSampleBits, atomicLoadUInt64)

        let rampStartValue = withUnsafeMutablePointer(to: &lastParameterStartBits, atomicLoadDouble)
        let rampEndValue = withUnsafeMutablePointer(to: &lastParameterEndBits, atomicLoadDouble)
        let peakDelta = withUnsafeMutablePointer(to: &peakParameterDeltaBits, atomicLoadDouble)
        let gainDB = withUnsafeMutablePointer(to: &lastGainDbBits, atomicLoadDouble)
        let gainLinear = withUnsafeMutablePointer(to: &lastGainLinearBits, atomicLoadDouble)
        let peakLinear = withUnsafeMutablePointer(to: &peakGainLinearBits, atomicLoadDouble)
        let rms = withUnsafeMutablePointer(to: &lastOutputRmsBits, atomicLoadDouble)

        #if DEBUG
        let rampTimeTotal = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &rampComputationTimeRaw))
        let gainTimeTotal = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &gainComputationTimeRaw))
        let rampTimingInvocations = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &rampTimingInvocationCountRaw))
        let gainTimingInvocations = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &gainTimingInvocationCountRaw))
        let averageRampTime = rampTimingInvocations == 0 ? 0.0 : Double(rampTimeTotal) / Double(rampTimingInvocations)
        let averageGainTime = gainTimingInvocations == 0 ? 0.0 : Double(gainTimeTotal) / Double(gainTimingInvocations)
        #else
        let averageRampTime = 0.0
        let averageGainTime = 0.0
        #endif

        return GainSmoothingMetrics(
            parameterRamps: ramps,
            gainApplications: gainOperations,
            samplesProcessed: processed,
            clippedSamples: clipped,
            lastRampStartSample: rampStart,
            lastRampEndSample: rampEnd,
            lastGainStartSample: gainStart,
            lastGainEndSample: gainEnd,
            lastRampLength: lastRampLength,
            lastRampStartValue: rampStartValue,
            lastRampEndValue: rampEndValue,
            peakObservedRampDelta: peakDelta,
            lastGainDB: gainDB,
            lastGainLinear: gainLinear,
            peakGainLinear: peakLinear,
            lastOutputRMS: rms,
            averageRampNanoseconds: averageRampTime,
            averageGainNanoseconds: averageGainTime
        )
    }

    // MARK: - Private Helpers

    private func updateRampMetrics(
        startValue: Double,
        endValue: Double,
        rampSamples: Int,
        startSample: UInt64,
        endSample: UInt64
    ) {
        OSAtomicAdd64Barrier(1, &rampInvocationCountRaw)
        atomicStoreInt64(Int64(rampSamples), &lastRampLengthRaw)
        withUnsafeMutablePointer(to: &lastParameterStartBits) { atomicStoreDouble(startValue, $0) }
        withUnsafeMutablePointer(to: &lastParameterEndBits) { atomicStoreDouble(endValue, $0) }
        withUnsafeMutablePointer(to: &lastRampStartSampleBits) { atomicStoreUInt64(startSample, $0) }
        withUnsafeMutablePointer(to: &lastRampEndSampleBits) { atomicStoreUInt64(endSample, $0) }
        withUnsafeMutablePointer(to: &peakParameterDeltaBits) {
            atomicUpdateMaxDouble(abs(endValue - startValue), $0)
        }
    }

    private func updateGainMetrics(
        gainDB: Double,
        gainLinear: Double,
        startSample: UInt64,
        endSample: UInt64,
        rms: Double,
        clippedSamples: UInt64,
        processedSamples: Int
    ) {
        OSAtomicAdd64Barrier(1, &gainInvocationCountRaw)
        OSAtomicAdd64Barrier(Int64(processedSamples), &totalSamplesProcessedRaw)
        if clippedSamples > 0 {
            OSAtomicAdd64Barrier(Int64(clippedSamples), &clippedSamplesRaw)
        }
        withUnsafeMutablePointer(to: &lastGainDbBits) { atomicStoreDouble(gainDB, $0) }
        withUnsafeMutablePointer(to: &lastGainLinearBits) { atomicStoreDouble(gainLinear, $0) }
        withUnsafeMutablePointer(to: &peakGainLinearBits) { atomicUpdateMaxDouble(gainLinear, $0) }
        withUnsafeMutablePointer(to: &lastOutputRmsBits) { atomicStoreDouble(rms, $0) }
        withUnsafeMutablePointer(to: &lastGainStartSampleBits) { atomicStoreUInt64(startSample, $0) }
        withUnsafeMutablePointer(to: &lastGainEndSampleBits) { atomicStoreUInt64(endSample, $0) }
    }

    @inline(__always)
    private func softClip(_ sample: Float) -> (sample: Float, clipped: Bool) {
        let threshold: Float = 0.975
        if sample.magnitude <= threshold {
            return (sample, false)
        }

        let over = sample.magnitude - threshold
        let knee: Float = 0.125
        let shaped = threshold + knee * tanhf(over / knee)
        let limited = min(1.0, shaped)
        let signed = copysignf(limited, sample)
        return (signed, true)
    }

    @inline(__always)
    private func smoothstep(_ t: Double) -> Double {
        var clamped = max(0.0, min(1.0, t))
        // Hermite polynomial with zero derivatives at the boundaries.
        clamped = clamped * clamped * (3.0 - 2.0 * clamped)
        return clamped
    }

    @inline(__always)
    private func hermiteInterpolation(t: Double, start: Double, end: Double) -> Double {
        let delta = end - start
        return fma(delta, t, start)
    }

    @inline(__always)
    private func dbToLinear(_ value: Double) -> Double {
        guard value > -Double.infinity else { return 0.0 }
        return exp2(value * 0.166_096_404_744_368) // 1 / (20 * log10(2))
    }

    @inline(__always)
    public func linearToDb(_ value: Double) -> Double {
        guard value > 0 else { return -Double.infinity }
        return 20.0 * log10(value)
    }
}

// MARK: - Atomic Utilities

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
    let bits = UInt64(bitPattern: OSAtomicAdd64Barrier(0, storage))
    return Double(bitPattern: bits)
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
private func atomicStoreUInt64(_ value: UInt64, _ storage: UnsafeMutablePointer<Int64>) {
    var current = OSAtomicAdd64Barrier(0, storage)
    let newBits = Int64(bitPattern: value)
    while !OSAtomicCompareAndSwap64Barrier(current, newBits, storage) {
        current = OSAtomicAdd64Barrier(0, storage)
    }
}

@inline(__always)
private func atomicLoadUInt64(_ storage: UnsafeMutablePointer<Int64>) -> UInt64 {
    UInt64(bitPattern: OSAtomicAdd64Barrier(0, storage))
}

@inline(__always)
private func atomicStoreInt64(_ value: Int64, _ storage: UnsafeMutablePointer<Int64>) {
    var current = OSAtomicAdd64Barrier(0, storage)
    while !OSAtomicCompareAndSwap64Barrier(current, value, storage) {
        current = OSAtomicAdd64Barrier(0, storage)
    }
}

@inline(__always)
private func atomicLoadInt64(_ storage: UnsafeMutablePointer<Int64>) -> Int64 {
    OSAtomicAdd64Barrier(0, storage)
}

// MARK: - Diagnostics Snapshot

public struct GainSmoothingMetrics: Sendable {
    public let parameterRamps: UInt64
    public let gainApplications: UInt64
    public let samplesProcessed: UInt64
    public let clippedSamples: UInt64
    public let lastRampStartSample: UInt64
    public let lastRampEndSample: UInt64
    public let lastGainStartSample: UInt64
    public let lastGainEndSample: UInt64
    public let lastRampLength: Int
    public let lastRampStartValue: Double
    public let lastRampEndValue: Double
    public let peakObservedRampDelta: Double
    public let lastGainDB: Double
    public let lastGainLinear: Double
    public let peakGainLinear: Double
    public let lastOutputRMS: Double
    public let averageRampNanoseconds: Double
    public let averageGainNanoseconds: Double
}
