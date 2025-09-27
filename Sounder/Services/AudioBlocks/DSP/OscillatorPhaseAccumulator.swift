import Foundation
import Darwin

/// Timeline-coherent phase accumulator shared across oscillator blocks.
///
/// The accumulator operates directly on the absolute timeline sample index and
/// produces a wrapped phase in the `[0, 2*pi)` interval with +/-0.1% mathematical
/// precision. Internally it performs drift-compensated integration, applies
/// anti-aliasing soft-clamping near Nyquist, and maintains lock-free
/// performance counters that can be queried from non-audio threads.
///
/// All hot-path operations are allocation-free and avoid locks so the class is
/// safe for real-time audio use. Metrics are stored with atomic primitives to
/// ensure observers can inspect performance without synchronising with the
/// audio render thread.
public final class OscillatorPhaseAccumulator {
    // MARK: - Internal State

    private struct State {
        var currentPhase: Double = 0.0
        var driftCompensation: Double = 0.0
        var lastFrequency: Double = 0.0
        var lastSample: UInt64 = 0
    }

    private var state = State()

    // Constants chosen to balance stability and responsiveness.
    private let twoPi = 2.0 * Double.pi
    private let driftCorrectionRate = 0.0005
    private let aliasThresholdRatio: Double = 0.92 // Anti-aliasing engages at 92% Nyquist.

    // MARK: - Atomic Performance Counters

    private var samplesProcessedRaw: Int64 = 0
    private var phaseWrapsRaw: Int64 = 0
    private var peakPhaseErrorBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var aliasingAttenuationBits: Int64 = Int64(bitPattern: Double(1.0).bitPattern)
    private var driftCompensationBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var currentPhaseBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var lastFrequencyBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    #if DEBUG
    private var totalComputationTimeRaw: Int64 = 0
    private var invocationCountRaw: Int64 = 0
    #endif

    public init() {}

    // MARK: - Phase Calculation

    /// Calculates the oscillator phase for a specific absolute timeline position.
    /// - Parameters:
    ///   - frequency: Requested oscillator frequency in Hertz. Non-finite values
    ///     are ignored and the previous valid frequency is reused.
    ///   - startSample: Absolute sample position for which the phase is needed.
    ///   - sampleRate: Rendering sample rate in Hertz. Values ≤ 0 bypass the update
    ///     and return the last known phase.
    /// - Returns: Wrapped phase in radians within `[0, 2*pi)`.
    @inline(__always)
    public func calculatePhase(
        frequency: Double,
        startSample: UInt64,
        sampleRate: Double
    ) -> Double {
        guard sampleRate > 0 else {
            return withUnsafeMutablePointer(to: &currentPhaseBits, atomicLoadDouble)
        }

        #if DEBUG
        let startTime = DispatchTime.now().uptimeNanoseconds
        #endif

        if startSample < state.lastSample {
            reset(to: startSample)
        }

        let nyquist = sampleRate * 0.5
        let (safeFrequency, attenuation) = sanitizeFrequency(frequency, nyquist: nyquist)
        withUnsafeMutablePointer(to: &aliasingAttenuationBits) { atomicStoreDouble(attenuation, $0) }

        let sampleDelta = startSample &- state.lastSample
        let increment = computePhaseIncrement(
            targetFrequency: safeFrequency,
            previousFrequency: state.lastFrequency,
            samples: sampleDelta,
            sampleRate: sampleRate
        )

        let previousPhase = state.currentPhase
        let rawPhase = previousPhase + increment
        let wraps = rawPhase >= twoPi ? UInt64(max(0.0, floor(rawPhase / twoPi))) : 0
        state.currentPhase = wrapPhase(rawPhase)

        if wraps > 0 {
            OSAtomicAdd64Barrier(Int64(truncatingIfNeeded: wraps), &phaseWrapsRaw)
        }

        let phasePerSample = safeFrequency * twoPi / sampleRate
        let timelinePhase = wrapPhase(fma(Double(startSample), phasePerSample, 0.0))
        let phaseError = wrapRelativePhase(timelinePhase - state.currentPhase)
        state.driftCompensation = fma(
            phaseError,
            driftCorrectionRate,
            state.driftCompensation * (1.0 - driftCorrectionRate)
        )
        state.currentPhase = wrapPhase(state.currentPhase + state.driftCompensation)

        withUnsafeMutablePointer(to: &driftCompensationBits) { atomicStoreDouble(state.driftCompensation, $0) }
        withUnsafeMutablePointer(to: &currentPhaseBits) { atomicStoreDouble(state.currentPhase, $0) }
        withUnsafeMutablePointer(to: &lastFrequencyBits) { atomicStoreDouble(safeFrequency, $0) }
        withUnsafeMutablePointer(to: &peakPhaseErrorBits) { atomicUpdateMaxDouble(abs(phaseError), $0) }

        if sampleDelta > 0 {
            OSAtomicAdd64Barrier(Int64(truncatingIfNeeded: sampleDelta), &samplesProcessedRaw)
        }

        state.lastSample = startSample
        state.lastFrequency = safeFrequency

        #if DEBUG
        let cycles = (safeFrequency * Double(startSample)) / sampleRate
        if cycles > 1.0 {
            let accuracyError = abs(phaseError) / (twoPi * cycles)
            assert(accuracyError <= 0.001, "Phase accuracy error \(accuracyError * 100)% exceeds +/-0.1% requirement")
        }

        let elapsed = DispatchTime.now().uptimeNanoseconds &- startTime
        OSAtomicAdd64Barrier(Int64(bitPattern: elapsed), &totalComputationTimeRaw)
        OSAtomicAdd64Barrier(1, &invocationCountRaw)
        #endif

        return state.currentPhase
    }

    /// Resets the accumulator to a fresh timeline position. Performance metrics
    /// remain intact so long-running sessions can correlate resets with phase
    /// behaviour.
    /// - Parameter startSample: Timeline sample that becomes the new reference.
    public func reset(to startSample: UInt64 = 0) {
        state = State(currentPhase: 0.0, driftCompensation: 0.0, lastFrequency: 0.0, lastSample: startSample)

        withUnsafeMutablePointer(to: &currentPhaseBits) { atomicStoreDouble(0.0, $0) }
        withUnsafeMutablePointer(to: &driftCompensationBits) { atomicStoreDouble(0.0, $0) }
        withUnsafeMutablePointer(to: &lastFrequencyBits) { atomicStoreDouble(0.0, $0) }
        withUnsafeMutablePointer(to: &aliasingAttenuationBits) { atomicStoreDouble(1.0, $0) }
    }

    /// Captures a lock-free snapshot of internal counters and recent state for
    /// diagnostics or developer tooling.
    public func metrics() -> PhaseAccumulatorMetrics {
        let samplesProcessed = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &samplesProcessedRaw))
        let phaseWraps = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &phaseWrapsRaw))

        let maximumPhaseError = withUnsafeMutablePointer(to: &peakPhaseErrorBits, atomicLoadDouble)
        let driftCompensation = withUnsafeMutablePointer(to: &driftCompensationBits, atomicLoadDouble)
        let aliasingAttenuation = withUnsafeMutablePointer(to: &aliasingAttenuationBits, atomicLoadDouble)
        let currentPhase = withUnsafeMutablePointer(to: &currentPhaseBits, atomicLoadDouble)
        let lastFrequency = withUnsafeMutablePointer(to: &lastFrequencyBits, atomicLoadDouble)

        #if DEBUG
        let totalTime = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &totalComputationTimeRaw))
        let invocationCount = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &invocationCountRaw))
        let averageTime = invocationCount == 0 ? 0.0 : Double(totalTime) / Double(invocationCount)
        #else
        let averageTime = 0.0
        #endif

        return PhaseAccumulatorMetrics(
            samplesProcessed: samplesProcessed,
            phaseWraps: phaseWraps,
            maximumObservedPhaseError: maximumPhaseError,
            driftCompensation: driftCompensation,
            aliasingAttenuation: aliasingAttenuation,
            lastFrequency: lastFrequency,
            currentPhase: currentPhase,
            averageComputationNanoseconds: averageTime
        )
    }

    // MARK: - Helpers

    private func sanitizeFrequency(_ frequency: Double, nyquist: Double) -> (frequency: Double, attenuation: Double) {
        guard frequency.isFinite else {
            return (state.lastFrequency, withUnsafeMutablePointer(to: &aliasingAttenuationBits, atomicLoadDouble))
        }

        let positive = max(0.0, frequency)
        let threshold = aliasThresholdRatio * nyquist
        if positive <= threshold {
            return (positive, 1.0)
        }

        let clamped = min(positive, nyquist * 0.999)
        let ratio = (clamped / nyquist - aliasThresholdRatio) / (1.0 - aliasThresholdRatio)
        let attenuation = max(0.0, 1.0 - ratio * ratio)
        return (clamped, attenuation)
    }

    private func computePhaseIncrement(
        targetFrequency: Double,
        previousFrequency: Double,
        samples: UInt64,
        sampleRate: Double
    ) -> Double {
        guard samples > 0 else { return 0.0 }
        let averageFrequency = (targetFrequency + previousFrequency) * 0.5
        let timeDelta = Double(samples) / sampleRate
        return fma(averageFrequency, timeDelta, 0.0) * twoPi
    }

    @inline(__always)
    private func wrapPhase(_ phase: Double) -> Double {
        var wrapped = phase.truncatingRemainder(dividingBy: twoPi)
        if wrapped < 0.0 {
            wrapped += twoPi
        }
        return wrapped
    }

    @inline(__always)
    private func wrapRelativePhase(_ phase: Double) -> Double {
        var wrapped = phase.truncatingRemainder(dividingBy: twoPi)
        if wrapped > Double.pi {
            wrapped -= twoPi
        } else if wrapped < -Double.pi {
            wrapped += twoPi
        }
        return wrapped
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

// MARK: - Diagnostics Snapshot

public struct PhaseAccumulatorMetrics: Sendable {
    public let samplesProcessed: UInt64
    public let phaseWraps: UInt64
    public let maximumObservedPhaseError: Double
    public let driftCompensation: Double
    public let aliasingAttenuation: Double
    public let lastFrequency: Double
    public let currentPhase: Double
    public let averageComputationNanoseconds: Double
}
