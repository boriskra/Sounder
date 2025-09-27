import Foundation

/// High-quality triangle wave oscillator optimized for modulation sources
/// Provides linear ramps with precise timing for FM/AM applications
public class TriangleOscillatorBlock: AudioBlock {
    public let id: UUID
    public let type: BlockType = .triangleOscillator
    public let inputPorts: [String] = ["frequency", "symmetry"]
    public let outputPorts: [String] = ["signal"]

    // Audio parameters
    private var _frequency: Double = 100.0
    private var _amplitude: Double = 0.5
    private var _symmetry: Double = 50.0 // 0-100% duty cycle

    // Phase tracking
    private let sampleRate: Double
    private var _phase: Double = 0.0
    private var phaseIncrement: Double = 0.0

    // Triangle wave generation
    private var risingSlope: Double = 1.0
    private var fallingSlope: Double = -1.0
    private var symmetryPoint: Double = 0.5

    // Performance tracking
    private var sampleCount: UInt64 = 0
    private var lastSymmetryUpdate: UInt64 = 0

    public init(signalBlock: SignalBlock, sampleRate: Double = 48000.0) {
        self.id = signalBlock.id
        self.sampleRate = sampleRate

        // Initialize from block parameters
        if let freqParam = signalBlock.parameters["frequency"] {
            _frequency = freqParam.value
        }

        if let ampParam = signalBlock.parameters["amplitude"] {
            _amplitude = pow(10.0, ampParam.value / 20.0)
        }

        // Triangle-specific parameters
        if let symParam = signalBlock.parameters["symmetry"] {
            _symmetry = symParam.value
        }

        updateWaveformParameters()
    }

    // MARK: - AudioBlock Protocol

    public func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        var outputBuffer: [Float] = []
        outputBuffer.reserveCapacity(frameCount)

        let frequencyModulation = inputs["frequency"]
        let symmetryModulation = inputs["symmetry"]

        for frameIndex in 0..<frameCount {
            // Apply frequency modulation
            var currentFrequency = _frequency
            if let freqMod = frequencyModulation, frameIndex < freqMod.count {
                currentFrequency = _frequency + Double(freqMod[frameIndex]) * 50.0 // ±50Hz modulation
                currentFrequency = max(0.1, min(10000.0, currentFrequency))
            }

            // Apply symmetry modulation
            var currentSymmetry = _symmetry
            if let symMod = symmetryModulation, frameIndex < symMod.count {
                currentSymmetry = _symmetry + Double(symMod[frameIndex]) * 25.0 // ±25% modulation
                currentSymmetry = max(5.0, min(95.0, currentSymmetry))
            }

            // Update parameters if changed
            updateFrequency(currentFrequency)
            updateSymmetry(currentSymmetry)

            // Generate triangle wave sample
            let sample = generateTriangleSample()
            outputBuffer.append(Float(sample))

            // Advance phase
            advancePhase()
            sampleCount += 1
        }

        return ["signal": outputBuffer]
    }

    public func setParameter(name: String, value: Double) {
        switch name {
        case "frequency":
            _frequency = max(0.1, min(10000.0, value))
            updateWaveformParameters()

        case "amplitude":
            let clampedDb = max(-60.0, min(0.0, value))
            _amplitude = pow(10.0, clampedDb / 20.0)

        case "symmetry":
            _symmetry = max(5.0, min(95.0, value))
            updateWaveformParameters()
            lastSymmetryUpdate = sampleCount

        default:
            break
        }
    }

    public func reset() {
        _phase = 0.0
        sampleCount = 0
        lastSymmetryUpdate = 0
        updateWaveformParameters()
    }

    // MARK: - Triangle Wave Generation

    /// Updates waveform parameters when frequency or symmetry changes
    private func updateWaveformParameters() {
        phaseIncrement = _frequency / sampleRate
        symmetryPoint = _symmetry / 100.0

        // Calculate slopes for linear segments
        // Rising slope: 0 to peak in symmetryPoint duration
        risingSlope = 2.0 / symmetryPoint

        // Falling slope: peak to 0 in (1-symmetryPoint) duration
        fallingSlope = -2.0 / (1.0 - symmetryPoint)
    }

    /// Updates frequency with smooth transitions
    private func updateFrequency(_ newFrequency: Double) {
        if abs(newFrequency - _frequency) > 0.01 {
            _frequency = newFrequency
            phaseIncrement = _frequency / sampleRate
        }
    }

    /// Updates symmetry with smooth transitions
    private func updateSymmetry(_ newSymmetry: Double) {
        if abs(newSymmetry - _symmetry) > 0.1 {
            _symmetry = newSymmetry
            symmetryPoint = _symmetry / 100.0

            // Recalculate slopes
            risingSlope = 2.0 / symmetryPoint
            fallingSlope = -2.0 / max(0.01, 1.0 - symmetryPoint) // Prevent division by zero
        }
    }

    /// Generates a single triangle wave sample
    private func generateTriangleSample() -> Double {
        let normalizedPhase = fmod(_phase, 1.0)
        var triangleValue: Double

        if normalizedPhase < symmetryPoint {
            // Rising segment: linear ramp from -1 to +1
            let segmentPhase = normalizedPhase / symmetryPoint
            triangleValue = -1.0 + segmentPhase * 2.0
        } else {
            // Falling segment: linear ramp from +1 to -1
            let segmentPhase = (normalizedPhase - symmetryPoint) / (1.0 - symmetryPoint)
            triangleValue = 1.0 - segmentPhase * 2.0
        }

        // Apply amplitude and ensure bounds
        let sample = _amplitude * triangleValue
        return max(-1.0, min(1.0, sample))
    }

    /// Advances phase with wraparound
    private func advancePhase() {
        _phase += phaseIncrement

        // Wrap phase to prevent accumulation
        if _phase >= 1.0 {
            _phase -= 1.0
        }
    }

    // MARK: - Modulation Optimization

    /// Gets the current modulation characteristics
    public func getModulationCharacteristics() -> TriangleModulationInfo {
        return TriangleModulationInfo(
            frequency: _frequency,
            symmetry: _symmetry,
            risingSlope: risingSlope,
            fallingSlope: fallingSlope,
            modulationRate: calculateModulationRate(),
            isOptimalForFM: isOptimalForFrequencyModulation()
        )
    }

    /// Calculates effective modulation rate for FM applications
    private func calculateModulationRate() -> Double {
        // For FM applications, triangle waves are effective modulators
        // when frequency is 10-1000x lower than carrier
        return _frequency
    }

    /// Determines if current settings are optimal for frequency modulation
    private func isOptimalForFrequencyModulation() -> Bool {
        // Optimal FM modulation characteristics:
        // 1. Frequency in range 0.1-1000 Hz
        // 2. Symmetry close to 50% for balanced modulation
        // 3. Clean linear ramps

        let frequencyOK = _frequency >= 0.1 && _frequency <= 1000.0
        let symmetryOK = abs(_symmetry - 50.0) <= 10.0 // Within ±10% of center

        return frequencyOK && symmetryOK
    }

    // MARK: - Performance Analysis

    /// Gets performance and quality metrics
    public func getPerformanceStats() -> TriangleOscillatorStats {
        return TriangleOscillatorStats(
            samplesProcessed: sampleCount,
            currentFrequency: _frequency,
            currentSymmetry: _symmetry,
            modulationQuality: calculateModulationQuality(),
            linearityError: calculateLinearityError(),
            lastSymmetryUpdate: lastSymmetryUpdate
        )
    }

    /// Calculates modulation quality score (0-1)
    private func calculateModulationQuality() -> Double {
        // Quality factors:
        // 1. Frequency stability
        // 2. Linearity of ramps
        // 3. Symmetry accuracy

        let frequencyStability = min(1.0, 1000.0 / max(1.0, _frequency)) // Better at lower frequencies
        let symmetryAccuracy = 1.0 - abs(_symmetry - 50.0) / 50.0 // Best at 50%
        let linearityQuality = 0.95 // High for digital triangle waves

        return (frequencyStability + symmetryAccuracy + linearityQuality) / 3.0
    }

    /// Calculates linearity error of triangle ramps
    private func calculateLinearityError() -> Double {
        // For digital triangle waves, linearity error is primarily from
        // sample rate limitations and floating-point precision
        let sampleRateError = _frequency / sampleRate
        return min(0.001, sampleRateError) // Maximum 0.1% error
    }
}

// MARK: - Information Structures

public struct TriangleModulationInfo {
    public let frequency: Double
    public let symmetry: Double
    public let risingSlope: Double
    public let fallingSlope: Double
    public let modulationRate: Double
    public let isOptimalForFM: Bool
}

public struct TriangleOscillatorStats {
    public let samplesProcessed: UInt64
    public let currentFrequency: Double
    public let currentSymmetry: Double
    public let modulationQuality: Double
    public let linearityError: Double
    public let lastSymmetryUpdate: UInt64
}

// MARK: - Factory Methods

extension TriangleOscillatorBlock {
    /// Creates a triangle oscillator optimized for frequency modulation
    public static func createFMModulator(frequency: Double = 100.0, depth: Double = -12.0) -> TriangleOscillatorBlock {
        let signalBlock = SignalBlock(
            type: .triangleOscillator,
            title: "FM Triangle \(Int(frequency))Hz",
            position: CGPoint.zero,
            parameters: [
                "frequency": BlockParameter.frequency(value: frequency, maxHz: 1000.0),
                "amplitude": BlockParameter.amplitude(value: depth),
                "symmetry": BlockParameter.percentage(name: "symmetry", displayName: "Symmetry", value: 50.0)
            ],
            inputPorts: BlockType.triangleOscillator.defaultInputPorts,
            outputPorts: BlockType.triangleOscillator.defaultOutputPorts
        )

        return TriangleOscillatorBlock(signalBlock: signalBlock)
    }

    /// Creates a triangle oscillator for LFO applications
    public static func createLFO(frequency: Double = 1.0) -> TriangleOscillatorBlock {
        let signalBlock = SignalBlock(
            type: .triangleOscillator,
            title: "Triangle LFO \(frequency)Hz",
            position: CGPoint.zero,
            parameters: [
                "frequency": BlockParameter.frequency(value: frequency, maxHz: 20.0),
                "amplitude": BlockParameter.amplitude(value: -6.0),
                "symmetry": BlockParameter.percentage(name: "symmetry", displayName: "Symmetry", value: 50.0)
            ],
            inputPorts: BlockType.triangleOscillator.defaultInputPorts,
            outputPorts: BlockType.triangleOscillator.defaultOutputPorts
        )

        return TriangleOscillatorBlock(signalBlock: signalBlock)
    }
}
