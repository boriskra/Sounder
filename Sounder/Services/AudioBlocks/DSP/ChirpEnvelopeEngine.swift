import Foundation
import Darwin

/// Chirp generator and envelope utility shared by the DSP audio blocks.
///
/// The engine produces linear and hyperbolic sweeps, maintains timeline-coherent
/// amplitude envelopes with smooth Hermite ramps, and captures performance
/// counters through OSAtomic primitives. A lightweight spinlock guards the
/// mutable state so real-time threads can coordinate sweep progression without
/// paying the cost of heavier synchronisation.
public final class ChirpEnvelopeEngine {
    private enum SweepKind: Int64 {
        case linear = 0
        case hyperbolic = 1
    }

    private struct EnvelopeState {
        var value: Double = 0.0
        var startValue: Double = 0.0
        var targetValue: Double = 0.0
        var rampStartSample: UInt64 = 0
        var rampEndSample: UInt64 = 0
        var lastSample: UInt64 = 0

        mutating func reset(value: Double, sample: UInt64) {
            self.value = value
            startValue = value
            targetValue = value
            rampStartSample = sample
            rampEndSample = sample
            lastSample = sample
        }
    }

    private struct State {
        var phase: Double = 0.0
        var cursor: UInt64 = 0
        var envelope = EnvelopeState()
        var lastSweep: SweepKind = .linear

        mutating func resetTimeline(sample: UInt64) {
            phase = 0.0
            cursor = sample
            envelope.reset(value: 0.0, sample: sample)
            lastSweep = .linear
        }
    }

    private var state = State()
    private var stateLock: Int32 = 0

    private let twoPi = 2.0 * Double.pi

    private var linearSweepCountRaw: Int64 = 0
    private var hyperbolicSweepCountRaw: Int64 = 0
    private var envelopeSamplesRaw: Int64 = 0
    private var timelineResetsRaw: Int64 = 0
    private var samplesRenderedRaw: Int64 = 0

    private var lastStartFrequencyBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var lastEndFrequencyBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var lastInstantFrequencyBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var lastSampleRateBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var lastAmplitudeBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var peakEnvelopeBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)
    private var lastSweepRaw: Int64 = SweepKind.linear.rawValue

    #if DEBUG
    private var totalRenderTimeRaw: Int64 = 0
    private var renderInvocationsRaw: Int64 = 0
    #endif

    public init() {
        state.envelope.reset(value: 0.0, sample: 0)
    }

    /// Generates a linear chirp over the requested frame window.
    public func generateLinearChirp(
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double,
        startFrequency: Double,
        endFrequency: Double,
        targetAmplitude: Double,
        rampSamples: Int = 0
    ) -> [Double] {
        renderChirp(
            kind: .linear,
            frameCount: frameCount,
            startSample: startSample,
            sampleRate: sampleRate,
            startFrequency: startFrequency,
            endFrequency: endFrequency,
            targetAmplitude: targetAmplitude,
            rampSamples: rampSamples
        )
    }

    /// Generates a hyperbolic chirp where the instantaneous frequency follows
    /// `f(t) = f0 / (1 + k * t)`.
    public func generateHyperbolicChirp(
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double,
        startFrequency: Double,
        endFrequency: Double,
        targetAmplitude: Double,
        rampSamples: Int = 0
    ) -> [Double] {
        renderChirp(
            kind: .hyperbolic,
            frameCount: frameCount,
            startSample: startSample,
            sampleRate: sampleRate,
            startFrequency: startFrequency,
            endFrequency: endFrequency,
            targetAmplitude: targetAmplitude,
            rampSamples: rampSamples
        )
    }

    /// Returns an envelope ramp aligned to the absolute timeline.
    public func generateEnvelope(
        frameCount: Int,
        startSample: UInt64,
        targetAmplitude: Double,
        rampSamples: Int
    ) -> [Double] {
        guard frameCount > 0 else { return [] }

        var envelopeValues = [Double](repeating: 0.0, count: frameCount)
        let sanitizedAmplitude = sanitizeAmplitude(targetAmplitude)
        var finalAmplitude = sanitizedAmplitude
        var peak = abs(sanitizedAmplitude)

        withLockedState { state in
            if startSample < state.cursor {
                state.resetTimeline(sample: startSample)
                OSAtomicAdd64Barrier(1, &timelineResetsRaw)
            } else if startSample > state.cursor {
                state.cursor = startSample
            }

            let outcome = prepareEnvelope(
                into: &envelopeValues,
                envelopeState: &state.envelope,
                startSample: startSample,
                targetAmplitude: sanitizedAmplitude,
                rampSamples: rampSamples
            )
            finalAmplitude = outcome.finalAmplitude
            peak = outcome.peak
            state.cursor = startSample &+ UInt64(frameCount)
        }

        OSAtomicAdd64Barrier(Int64(frameCount), &envelopeSamplesRaw)
        withUnsafeMutablePointer(to: &lastAmplitudeBits) { atomicStoreDouble(finalAmplitude, $0) }
        withUnsafeMutablePointer(to: &peakEnvelopeBits) { atomicUpdateMaxDouble(peak, $0) }

        return envelopeValues
    }

    /// Multiplies the supplied buffer by an internally generated amplitude ramp.
    public func applyAmplitudeRamp(
        to buffer: inout [Double],
        startSample: UInt64,
        targetAmplitude: Double,
        rampSamples: Int
    ) {
        guard !buffer.isEmpty else { return }

        var envelopeValues = [Double](repeating: 0.0, count: buffer.count)
        let sanitizedAmplitude = sanitizeAmplitude(targetAmplitude)
        var peak = abs(sanitizedAmplitude)

        withLockedState { state in
            if startSample < state.cursor {
                state.resetTimeline(sample: startSample)
                OSAtomicAdd64Barrier(1, &timelineResetsRaw)
            } else if startSample > state.cursor {
                state.cursor = startSample
            }

            let outcome = prepareEnvelope(
                into: &envelopeValues,
                envelopeState: &state.envelope,
                startSample: startSample,
                targetAmplitude: sanitizedAmplitude,
                rampSamples: rampSamples
            )
            peak = outcome.peak
            state.cursor = startSample &+ UInt64(buffer.count)
        }

        for index in 0..<buffer.count {
            buffer[index] *= envelopeValues[index]
        }

        OSAtomicAdd64Barrier(Int64(buffer.count), &envelopeSamplesRaw)
        withUnsafeMutablePointer(to: &lastAmplitudeBits) { atomicStoreDouble(envelopeValues.last ?? sanitizedAmplitude, $0) }
        withUnsafeMutablePointer(to: &peakEnvelopeBits) { atomicUpdateMaxDouble(peak, $0) }
    }

    /// Snapshot of the atomic counters and last render parameters.
    public func metrics() -> ChirpEnvelopeMetrics {
        let linear = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &linearSweepCountRaw))
        let hyperbolic = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &hyperbolicSweepCountRaw))
        let envelopeSamples = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &envelopeSamplesRaw))
        let timelineResets = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &timelineResetsRaw))
        let samplesRendered = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &samplesRenderedRaw))

        let lastStart = withUnsafeMutablePointer(to: &lastStartFrequencyBits, atomicLoadDouble)
        let lastEnd = withUnsafeMutablePointer(to: &lastEndFrequencyBits, atomicLoadDouble)
        let lastInstant = withUnsafeMutablePointer(to: &lastInstantFrequencyBits, atomicLoadDouble)
        let lastRate = withUnsafeMutablePointer(to: &lastSampleRateBits, atomicLoadDouble)
        let lastAmplitude = withUnsafeMutablePointer(to: &lastAmplitudeBits, atomicLoadDouble)
        let peakEnvelope = withUnsafeMutablePointer(to: &peakEnvelopeBits, atomicLoadDouble)

        let sweepRaw = OSAtomicAdd64Barrier(0, &lastSweepRaw)
        let sweepKind = ChirpEnvelopeMetrics.SweepKind(rawValue: sweepRaw) ?? .linear

        #if DEBUG
        let totalTime = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &totalRenderTimeRaw))
        let renderCount = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &renderInvocationsRaw))
        let average = renderCount > 0 ? Double(totalTime) / Double(renderCount) : 0.0
        #else
        let average = 0.0
        #endif

        return ChirpEnvelopeMetrics(
            samplesRendered: samplesRendered,
            linearSweeps: linear,
            hyperbolicSweeps: hyperbolic,
            envelopeSamples: envelopeSamples,
            timelineResets: timelineResets,
            lastStartFrequency: lastStart,
            lastEndFrequency: lastEnd,
            lastInstantFrequency: lastInstant,
            lastSampleRate: lastRate,
            lastAmplitude: lastAmplitude,
            peakEnvelope: peakEnvelope,
            lastSweepKind: sweepKind,
            averageRenderNanoseconds: average
        )
    }

    // MARK: - Core Rendering

    private func renderChirp(
        kind: SweepKind,
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double,
        startFrequency: Double,
        endFrequency: Double,
        targetAmplitude: Double,
        rampSamples: Int
    ) -> [Double] {
        guard frameCount > 0, sampleRate > 0 else { return [] }

        var output = [Double](repeating: 0.0, count: frameCount)
        let sanitizedStart = sanitizeFrequency(startFrequency)
        let sanitizedEnd = sanitizeFrequency(endFrequency)
        let sanitizedAmplitude = sanitizeAmplitude(targetAmplitude)
        var finalAmplitude = sanitizedAmplitude
        var peakEnvelope = abs(sanitizedAmplitude)
        var lastFrequency = sanitizedStart

        #if DEBUG
        let timingStart = DispatchTime.now().uptimeNanoseconds
        #endif

        withLockedState { state in
            if startSample < state.cursor {
                state.resetTimeline(sample: startSample)
                OSAtomicAdd64Barrier(1, &timelineResetsRaw)
            } else if startSample > state.cursor {
                state.cursor = startSample
            }

            var envelope = [Double](repeating: state.envelope.value, count: frameCount)
            let envelopeOutcome = prepareEnvelope(
                into: &envelope,
                envelopeState: &state.envelope,
                startSample: startSample,
                targetAmplitude: sanitizedAmplitude,
                rampSamples: rampSamples
            )
            finalAmplitude = envelopeOutcome.finalAmplitude
            peakEnvelope = envelopeOutcome.peak

            let phaseScale = twoPi / sampleRate
            var phase = state.phase
            let dt = 1.0 / sampleRate
            let samplesForSlope = max(frameCount - 1, 1)
            let totalDurationSeconds = Double(samplesForSlope) * dt

            let slope: Double
            let beta: Double
            switch kind {
            case .linear:
                slope = totalDurationSeconds > 0.0 ? (sanitizedEnd - sanitizedStart) / totalDurationSeconds : 0.0
                beta = 0.0
            case .hyperbolic:
                slope = 0.0
                let startPositive = max(sanitizedStart, 1.0e-9)
                let endPositive = max(sanitizedEnd, 1.0e-9)
                beta = totalDurationSeconds > 0.0 ? ((startPositive / endPositive) - 1.0) / totalDurationSeconds : 0.0
            }

            for index in 0..<frameCount {
                let time = Double(index) * dt
                let frequency: Double
                switch kind {
                case .linear:
                    frequency = max(0.0, sanitizedStart + slope * time)
                case .hyperbolic:
                    let denominator = max(1.0 + beta * time, 1.0e-9)
                    frequency = max(0.0, sanitizedStart / denominator)
                }

                phase = wrapPhase(phase + frequency * phaseScale)
                output[index] = sin(phase) * envelope[index]
                lastFrequency = frequency
            }

            state.phase = phase
            state.cursor = startSample &+ UInt64(frameCount)
            state.lastSweep = kind
        }

        #if DEBUG
        let elapsed = Int64(DispatchTime.now().uptimeNanoseconds &- timingStart)
        OSAtomicAdd64Barrier(elapsed, &totalRenderTimeRaw)
        OSAtomicAdd64Barrier(1, &renderInvocationsRaw)
        #endif

        OSAtomicAdd64Barrier(Int64(frameCount), &samplesRenderedRaw)

        switch kind {
        case .linear:
            OSAtomicAdd64Barrier(1, &linearSweepCountRaw)
        case .hyperbolic:
            OSAtomicAdd64Barrier(1, &hyperbolicSweepCountRaw)
        }

        withUnsafeMutablePointer(to: &lastSweepRaw) { atomicStoreInt64(kind.rawValue, $0) }
        withUnsafeMutablePointer(to: &lastStartFrequencyBits) { atomicStoreDouble(sanitizedStart, $0) }
        withUnsafeMutablePointer(to: &lastEndFrequencyBits) { atomicStoreDouble(sanitizedEnd, $0) }
        withUnsafeMutablePointer(to: &lastInstantFrequencyBits) { atomicStoreDouble(lastFrequency, $0) }
        withUnsafeMutablePointer(to: &lastSampleRateBits) { atomicStoreDouble(sampleRate, $0) }
        withUnsafeMutablePointer(to: &lastAmplitudeBits) { atomicStoreDouble(finalAmplitude, $0) }
        withUnsafeMutablePointer(to: &peakEnvelopeBits) { atomicUpdateMaxDouble(peakEnvelope, $0) }

        return output
    }

    private func prepareEnvelope(
        into buffer: inout [Double],
        envelopeState: inout EnvelopeState,
        startSample: UInt64,
        targetAmplitude: Double,
        rampSamples: Int
    ) -> (finalAmplitude: Double, peak: Double) {
        guard !buffer.isEmpty else {
            return (envelopeState.value, abs(envelopeState.value))
        }

        if startSample < envelopeState.lastSample {
            envelopeState.reset(value: 0.0, sample: startSample)
        } else if startSample > envelopeState.lastSample {
            envelopeState.lastSample = startSample
        }

        let rampCount = max(0, rampSamples)
        if rampCount <= 0 {
            for index in 0..<buffer.count {
                buffer[index] = targetAmplitude
            }
            envelopeState.value = targetAmplitude
            envelopeState.startValue = targetAmplitude
            envelopeState.targetValue = targetAmplitude
            envelopeState.rampStartSample = startSample
            envelopeState.rampEndSample = startSample
            envelopeState.lastSample = startSample &+ UInt64(buffer.count - 1)
            return (targetAmplitude, abs(targetAmplitude))
        }

        envelopeState.startValue = envelopeState.value
        envelopeState.targetValue = targetAmplitude
        envelopeState.rampStartSample = startSample
        let rampLength = UInt64(max(1, rampCount))
        envelopeState.rampEndSample = startSample &+ rampLength

        var peak: Double = 0.0
        let denominator = Double(max(1, envelopeState.rampEndSample &- envelopeState.rampStartSample))

        for index in 0..<buffer.count {
            let currentSample = startSample &+ UInt64(index)
            let value: Double
            if currentSample >= envelopeState.rampEndSample {
                value = envelopeState.targetValue
            } else {
                let progress = Double(currentSample &- envelopeState.rampStartSample) / denominator
                let shaped = smoothstep(progress)
                value = hermiteInterpolation(t: shaped, start: envelopeState.startValue, end: envelopeState.targetValue)
            }

            buffer[index] = value
            peak = max(peak, abs(value))
            envelopeState.value = value
            envelopeState.lastSample = currentSample
        }

        return (envelopeState.value, peak)
    }

    // MARK: - Helpers

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

    @inline(__always)
    private func sanitizeFrequency(_ frequency: Double) -> Double {
        guard frequency.isFinite else { return 0.0 }
        return max(0.0, frequency)
    }

    @inline(__always)
    private func sanitizeAmplitude(_ amplitude: Double) -> Double {
        guard amplitude.isFinite else { return 0.0 }
        return amplitude
    }

    @inline(__always)
    private func wrapPhase(_ phase: Double) -> Double {
        var wrapped = phase
        if wrapped >= twoPi || wrapped < 0.0 {
            wrapped = wrapped.truncatingRemainder(dividingBy: twoPi)
            if wrapped < 0.0 {
                wrapped += twoPi
            }
        }
        return wrapped
    }

    @inline(__always)
    private func smoothstep(_ t: Double) -> Double {
        let clamped = max(0.0, min(1.0, t))
        return clamped * clamped * (3.0 - 2.0 * clamped)
    }

    @inline(__always)
    private func hermiteInterpolation(t: Double, start: Double, end: Double) -> Double {
        return fma(end - start, t, start)
    }
}

// MARK: - Diagnostics Snapshot

public struct ChirpEnvelopeMetrics: Sendable {
    public enum SweepKind: Int64, Sendable {
        case linear = 0
        case hyperbolic = 1
    }

    public let samplesRendered: UInt64
    public let linearSweeps: UInt64
    public let hyperbolicSweeps: UInt64
    public let envelopeSamples: UInt64
    public let timelineResets: UInt64
    public let lastStartFrequency: Double
    public let lastEndFrequency: Double
    public let lastInstantFrequency: Double
    public let lastSampleRate: Double
    public let lastAmplitude: Double
    public let peakEnvelope: Double
    public let lastSweepKind: SweepKind
    public let averageRenderNanoseconds: Double
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
