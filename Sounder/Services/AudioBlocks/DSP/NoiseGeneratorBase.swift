import Foundation
import Darwin

/// Lightweight white-noise generator shared by Sounder's DSP blocks.
/// Deterministic for a given seed + `startSample`, thread-safe via a spinlock,
/// and exposes cheap per-render quality metrics stored through OSAtomic.
public final class NoiseGeneratorBase {
    // MARK: Public API

    /// Default seed value used when no explicit seed is supplied.
    public static let defaultSeed: UInt64 = 0x8ECF_13A5_9472_BC4D

    /// Creates a generator configured for white noise production.
    /// - Parameters:
    ///   - seed: Random seed driving the underlying Mersenne Twister.
    ///   - bandwidthLimit: Optional low-pass cutoff to apply to the output.
    public init(seed: UInt64 = NoiseGeneratorBase.defaultSeed, bandwidthLimit: Double? = nil) {
        baseSeed = seed
        state = State(seed: seed, cutoff: bandwidthLimit)
        withUnsafeMutablePointer(to: &bandwidthCutoffBits) { atomicStoreDouble(bandwidthLimit ?? .nan, $0) }
    }

    /// Generates deterministic white noise for the requested timeline window.
    /// - Parameters:
    ///   - frameCount: Number of frames to synthesize.
    ///   - startSample: Absolute timeline sample for the first frame.
    ///   - sampleRate: Sample rate used to shape the bandwidth limiter.
    ///   - overrideBandwidth: Optional per-call cutoff that overrides the current limit.
    /// - Returns: Array of doubles representing the rendered noise.
    public func generate(
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double,
        bandwidth overrideBandwidth: Double? = nil
    ) -> [Double] {
        guard frameCount > 0 else { return [] }

        var buffer: [Double] = [Double](repeating: 0.0, count: frameCount)
        let outcome: RenderOutcome = withLockedState { state -> RenderOutcome in
            let effectiveCutoff: Double? = overrideBandwidth ?? state.lowpass.cutoff
            state.lowpass.update(cutoff: effectiveCutoff, sampleRate: sampleRate)
            state.sampleRate = sampleRate

            synchronise(&state, to: startSample)

            var sum: Double = 0.0
            var sumSquares: Double = 0.0
            var peak: Double = 0.0

            for index in 0..<frameCount {
                let sample: Double = produceSample(state: &state)
                buffer[index] = sample
                sum += sample
                sumSquares += sample * sample
                peak = max(peak, sample.magnitude)
            }

            let count: Double = Double(frameCount)
            let mean: Double = sum / count
            let rms: Double = sqrt(max(sumSquares / count, 0.0))

            return RenderOutcome(
                mean: mean,
                rms: rms,
                peak: peak,
                frameCount: frameCount,
                cutoff: state.lowpass.cutoff
            )
        }

        updateMetrics(outcome)
        return buffer
    }

    /// Updates the persistent bandwidth limiter cutoff.
    /// - Parameter cutoff: Optional cutoff in hertz; `nil` disables the filter.
    public func setBandwidthLimit(_ cutoff: Double?) {
        withLockedState { state in
            state.lowpass.update(cutoff: cutoff, sampleRate: state.sampleRate)
        }
        withUnsafeMutablePointer(to: &bandwidthCutoffBits) { atomicStoreDouble(cutoff ?? .nan, $0) }
    }

    /// Resets the generator to the supplied timeline position.
    /// - Parameter startSample: Absolute sample position to align the generator with.
    public func reset(to startSample: UInt64 = 0) {
        withLockedState { state in
            reseed(&state)
            if startSample > 0 {
                skip(&state, samples: startSample)
            }
        }
    }

    /// Reseeds the generator with a new random seed or a specified value.
    /// - Parameter seed: Optional explicit seed. If omitted a random seed is used.
    public func reseed(with seed: UInt64? = nil) {
        let newSeed = seed ?? UInt64.random(in: UInt64.min...UInt64.max)
        let cutoff = withLockedState { state -> Double? in
            baseSeed = newSeed
            let currentCutoff = state.lowpass.cutoff
            reseed(&state)
            state.lowpass.update(cutoff: currentCutoff, sampleRate: state.sampleRate)
            return currentCutoff
        }

        withUnsafeMutablePointer(to: &samplesGeneratedRaw) { atomicStoreInt64(0, $0) }
        withUnsafeMutablePointer(to: &meanBits) { atomicStoreDouble(0.0, $0) }
        withUnsafeMutablePointer(to: &rmsBits) { atomicStoreDouble(0.0, $0) }
        withUnsafeMutablePointer(to: &peakBits) { atomicStoreDouble(0.0, $0) }
        withUnsafeMutablePointer(to: &bandwidthCutoffBits) { atomicStoreDouble(cutoff ?? .nan, $0) }
    }

    /// Returns the most recent quality metrics captured by atomic counters.
    public func metrics() -> NoiseGeneratorMetrics {
        let renderedSamples: UInt64 = withUnsafeMutablePointer(to: &samplesGeneratedRaw) {
            UInt64(bitPattern: atomicLoadInt64($0))
        }
        let mean: Double = withUnsafeMutablePointer(to: &meanBits, atomicLoadDouble)
        let rms: Double = withUnsafeMutablePointer(to: &rmsBits, atomicLoadDouble)
        let peak: Double = withUnsafeMutablePointer(to: &peakBits, atomicLoadDouble)
        let cutoffValue: Double = withUnsafeMutablePointer(to: &bandwidthCutoffBits, atomicLoadDouble)

        let cutoff: Double? = cutoffValue.isFinite && cutoffValue > 0 ? cutoffValue : nil

        return NoiseGeneratorMetrics(
            samplesGenerated: renderedSamples,
            mean: mean,
            rms: rms,
            peak: peak,
            bandwidthCutoff: cutoff
        )
    }

    // MARK: Internal State & Rendering

    private struct State {
        var engine: MT19937
        var cursor: UInt64
        var lowpass: Lowpass
        var sampleRate: Double

        init(seed: UInt64, cutoff: Double?) {
            engine = MT19937(seed: seed)
            cursor = 0
            sampleRate = NoiseGeneratorBase.defaultSampleRate
            lowpass = Lowpass(cutoff: cutoff, sampleRate: sampleRate)
        }
    }

    private struct RenderOutcome {
        let mean: Double
        let rms: Double
        let peak: Double
        let frameCount: Int
        let cutoff: Double?
    }

    private func synchronise(_ state: inout State, to startSample: UInt64) {
        if startSample < state.cursor {
            reseed(&state)
            if startSample > 0 {
                skip(&state, samples: startSample)
            }
        } else if startSample > state.cursor {
            skip(&state, samples: startSample &- state.cursor)
        }
    }

    private func reseed(_ state: inout State) {
        state.engine.reseed(with: baseSeed)
        state.cursor = 0
        state.lowpass.reset()
    }

    private func skip(_ state: inout State, samples: UInt64) {
        guard samples > 0 else { return }
        var remaining: UInt64 = samples
        while remaining > 0 {
            let chunk: Int = Int(min(remaining, 256))
            for _ in 0..<chunk {
                _ = produceSample(state: &state)
            }
            remaining &-= UInt64(chunk)
        }
    }

    @inline(__always)
    private func produceSample(state: inout State) -> Double {
        let white: Double = state.engine.nextDoubleSymmetric()
        let limited: Double = state.lowpass.process(white)
        state.cursor &+= 1
        return clamp(limited)
    }

    private func updateMetrics(_ outcome: RenderOutcome) {
        guard outcome.frameCount > 0 else { return }
        withUnsafeMutablePointer(to: &samplesGeneratedRaw) { pointer in
            _ = atomicAddInt64(Int64(outcome.frameCount), pointer)
        }
        withUnsafeMutablePointer(to: &meanBits) { atomicStoreDouble(outcome.mean, $0) }
        withUnsafeMutablePointer(to: &rmsBits) { atomicStoreDouble(outcome.rms, $0) }
        withUnsafeMutablePointer(to: &peakBits) { atomicStoreDouble(outcome.peak, $0) }
        withUnsafeMutablePointer(to: &bandwidthCutoffBits) { atomicStoreDouble(outcome.cutoff ?? .nan, $0) }
    }

    // MARK: Synchronisation Helpers

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

    // MARK: Stored Properties

    private static let defaultSampleRate: Double = 48_000.0

    private var baseSeed: UInt64
    private var state: State
    private var stateLock: Int32 = 0

    private var samplesGeneratedRaw: Int64 = 0
    private var meanBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var rmsBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var peakBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var bandwidthCutoffBits: Int64 = Int64(bitPattern: Double.nan.bitPattern)
}

// MARK: Diagnostics

/// Snapshot of the generator's atomic counters.
public struct NoiseGeneratorMetrics: Sendable {
    /// Total number of samples rendered through `generate` calls.
    public let samplesGenerated: UInt64
    /// Mean of the most recent render pass.
    public let mean: Double
    /// Root-mean-square amplitude of the most recent render pass.
    public let rms: Double
    /// Peak magnitude captured during the most recent render pass.
    public let peak: Double
    /// Effective bandwidth cutoff in hertz, if enabled.
    public let bandwidthCutoff: Double?
}

// MARK: - Mersenne Twister

private struct SplitMix64 {
    private var stateValue: UInt64

    init(seed: UInt64) {
        stateValue = seed
    }

    mutating func next() -> UInt64 {
        stateValue &+= 0x9E37_79B9_7F4A_7C15
        var mixed: UInt64 = stateValue
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

private struct MT19937 {
    private static let stateLength: Int = 624
    private static let middlePeriod: Int = 397
    private static let matrixCoefficient: UInt32 = 0x9908_B0DF
    private static let upperMask: UInt32 = 0x8000_0000
    private static let lowerMask: UInt32 = 0x7FFF_FFFF

    private var state: [UInt32] = [UInt32](repeating: 0, count: MT19937.stateLength)
    private var stateIndex: Int = MT19937.stateLength

    init(seed: UInt64) {
        self.init()
        reseed(with: seed)
    }

    init() {}

    mutating func reseed(with seed: UInt64) {
        var seeder: SplitMix64 = SplitMix64(seed: seed)
        for elementIndex in 0..<MT19937.stateLength {
            state[elementIndex] = UInt32(truncatingIfNeeded: seeder.next())
        }
        stateIndex = MT19937.stateLength
    }

    mutating func nextUInt32() -> UInt32 {
        if stateIndex >= MT19937.stateLength {
            twist()
        }
        var temperedValue: UInt32 = state[stateIndex]
        temperedValue ^= temperedValue >> 11
        temperedValue ^= (temperedValue << 7) & 0x9D2C_5680
        temperedValue ^= (temperedValue << 15) & 0xEFC6_0000
        temperedValue ^= temperedValue >> 18
        stateIndex &+= 1
        return temperedValue
    }

    mutating func nextDoubleSymmetric() -> Double {
        let highBits: UInt64 = UInt64(nextUInt32() >> 5)
        let lowBits: UInt64 = UInt64(nextUInt32() >> 6)
        let combinedMantissa: UInt64 = (highBits << 27) | lowBits
        return (Double(combinedMantissa) * (1.0 / Double(1 << 53))) * 2.0 - 1.0
    }

    private mutating func twist() {
        for elementIndex in 0..<MT19937.stateLength {
            let combinedBits: UInt32 = (state[elementIndex] & MT19937.upperMask) | (state[(elementIndex + 1) % MT19937.stateLength] & MT19937.lowerMask)
            var twistedBits: UInt32 = combinedBits >> 1
            if (combinedBits & 1) != 0 {
                twistedBits ^= MT19937.matrixCoefficient
            }
            state[elementIndex] = state[(elementIndex + MT19937.middlePeriod) % MT19937.stateLength] ^ twistedBits
        }
        stateIndex = 0
    }
}

// MARK: - Lowpass Filter

private struct Lowpass {
    private(set) var cutoff: Double?
    private(set) var sampleRate: Double
    private var alpha: Double
    private var lastOutput: Double

    init(cutoff: Double?, sampleRate: Double) {
        self.cutoff = cutoff
        self.sampleRate = sampleRate
        alpha = Lowpass.computeAlpha(cutoff: cutoff, sampleRate: sampleRate)
        lastOutput = 0.0
    }

    mutating func update(cutoff: Double?, sampleRate: Double) {
        self.cutoff = cutoff
        self.sampleRate = sampleRate
        alpha = Lowpass.computeAlpha(cutoff: cutoff, sampleRate: sampleRate)
        if cutoff == nil {
            lastOutput = 0.0
        }
    }

    mutating func reset() {
        lastOutput = 0.0
    }

    mutating func process(_ input: Double) -> Double {
        guard let cutoff, cutoff > 0.0, cutoff < sampleRate * 0.5 else {
            lastOutput = input
            return input
        }
        let outputValue: Double = alpha * input + (1.0 - alpha) * lastOutput
        lastOutput = outputValue
        return outputValue
    }

    private static func computeAlpha(cutoff: Double?, sampleRate: Double) -> Double {
        guard let cutoff, cutoff > 0.0, sampleRate > 0.0, cutoff < sampleRate * 0.5 else {
            return 1.0
        }
        return 1.0 - exp(-2.0 * Double.pi * cutoff / sampleRate)
    }
}

// MARK: - Atomic Helpers

@inline(__always)
private func clamp(_ value: Double) -> Double {
    if value > 1.0 { return 1.0 }
    if value < -1.0 { return -1.0 }
    return value
}

@inline(__always)
private func atomicStoreInt64(_ value: Int64, _ storage: UnsafeMutablePointer<Int64>) {
    while true {
        let current = storage.pointee
        if OSAtomicCompareAndSwap64Barrier(current, value, storage) {
            return
        }
    }
}

@inline(__always)
private func atomicLoadInt64(_ storage: UnsafeMutablePointer<Int64>) -> Int64 {
    while true {
        let current = storage.pointee
        if OSAtomicCompareAndSwap64Barrier(current, current, storage) {
            return current
        }
    }
}

@inline(__always)
@discardableResult
private func atomicAddInt64(_ value: Int64, _ storage: UnsafeMutablePointer<Int64>) -> Int64 {
    while true {
        let current = atomicLoadInt64(storage)
        let updated = current &+ value
        if OSAtomicCompareAndSwap64Barrier(current, updated, storage) {
            return updated
        }
    }
}

@inline(__always)
private func atomicStoreDouble(_ value: Double, _ storage: UnsafeMutablePointer<Int64>) {
    atomicStoreInt64(Int64(bitPattern: value.bitPattern), storage)
}

@inline(__always)
private func atomicLoadDouble(_ storage: UnsafeMutablePointer<Int64>) -> Double {
    Double(bitPattern: UInt64(bitPattern: atomicLoadInt64(storage)))
}
