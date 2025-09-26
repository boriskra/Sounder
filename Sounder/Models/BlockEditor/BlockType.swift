import Foundation
import SwiftUI

/// Defines the available signal processing block types
/// Each type corresponds to a specific audio processing function
public enum BlockType: String, CaseIterable, Codable, Equatable, Hashable {
    // MARK: - Generators
    case sineOscillator = "sine_oscillator"
    case squareOscillator = "square_oscillator"
    case triangleOscillator = "triangle_oscillator"
    case sawtoothOscillator = "sawtooth_oscillator"
    case whiteNoise = "white_noise"
    case pinkNoise = "pink_noise"
    case linearChirp = "linear_chirp"
    case hyperbolicChirp = "hyperbolic_chirp"

    // MARK: - Modulation
    case amplitudeModulator = "amplitude_modulator"
    case frequencyModulator = "frequency_modulator"
    case ringModulator = "ring_modulator"

    // MARK: - Processing
    case lowPassFilter = "low_pass_filter"
    case highPassFilter = "high_pass_filter"
    case bandPassFilter = "band_pass_filter"
    case mixer = "mixer"
    case amplifier = "amplifier"

    // MARK: - Analysis
    case spectrumAnalyzer = "spectrum_analyzer"
    case levelMeter = "level_meter"
    case frequencyCounter = "frequency_counter"

    // MARK: - Output
    case audioOutput = "audio_output"

    /// Human-readable display name for the block type
    public var displayName: String {
        switch self {
        // Generators
        case .sineOscillator: return "Sine Oscillator"
        case .squareOscillator: return "Square Oscillator"
        case .triangleOscillator: return "Triangle Oscillator"
        case .sawtoothOscillator: return "Sawtooth Oscillator"
        case .whiteNoise: return "White Noise"
        case .pinkNoise: return "Pink Noise"
        case .linearChirp: return "Linear Chirp"
        case .hyperbolicChirp: return "Hyperbolic Chirp"

        // Modulation
        case .amplitudeModulator: return "Amplitude Modulator"
        case .frequencyModulator: return "Frequency Modulator"
        case .ringModulator: return "Ring Modulator"

        // Processing
        case .lowPassFilter: return "Low Pass Filter"
        case .highPassFilter: return "High Pass Filter"
        case .bandPassFilter: return "Band Pass Filter"
        case .mixer: return "Mixer"
        case .amplifier: return "Amplifier"

        // Analysis
        case .spectrumAnalyzer: return "Spectrum Analyzer"
        case .levelMeter: return "Level Meter"
        case .frequencyCounter: return "Frequency Counter"

        // Output
        case .audioOutput: return "Audio Output"
        }
    }

    /// Short description of what the block does
    public var blockDescription: String {
        switch self {
        // Generators
        case .sineOscillator: return "Generates pure sine wave signals"
        case .squareOscillator: return "Generates square wave signals with adjustable duty cycle"
        case .triangleOscillator: return "Generates triangle wave signals"
        case .sawtoothOscillator: return "Generates sawtooth wave signals"
        case .whiteNoise: return "Generates white noise with equal power across frequencies"
        case .pinkNoise: return "Generates pink noise with 1/f frequency distribution"
        case .linearChirp: return "Generates frequency sweeps with linear rate change"
        case .hyperbolicChirp: return "Generates frequency sweeps optimized for cross-correlation"

        // Modulation
        case .amplitudeModulator: return "Modulates signal amplitude with control input"
        case .frequencyModulator: return "Modulates signal frequency with control input"
        case .ringModulator: return "Multiplies two signals for ring modulation effects"

        // Processing
        case .lowPassFilter: return "Removes frequencies above cutoff frequency"
        case .highPassFilter: return "Removes frequencies below cutoff frequency"
        case .bandPassFilter: return "Allows frequencies within specified band"
        case .mixer: return "Combines multiple signals with level control"
        case .amplifier: return "Adjusts signal gain and level"

        // Analysis
        case .spectrumAnalyzer: return "Real-time frequency spectrum visualization"
        case .levelMeter: return "Measures signal peak and RMS levels"
        case .frequencyCounter: return "Measures dominant frequency of input signal"

        // Output
        case .audioOutput: return "Routes audio to selected output device"
        }
    }

    /// Category grouping for UI organization
    public var category: BlockCategory {
        switch self {
        case .sineOscillator, .squareOscillator, .triangleOscillator, .sawtoothOscillator,
             .whiteNoise, .pinkNoise, .linearChirp, .hyperbolicChirp:
            return .generators

        case .amplitudeModulator, .frequencyModulator, .ringModulator:
            return .modulation

        case .lowPassFilter, .highPassFilter, .bandPassFilter, .mixer, .amplifier:
            return .processing

        case .spectrumAnalyzer, .levelMeter, .frequencyCounter:
            return .analysis

        case .audioOutput:
            return .output
        }
    }

    /// Whether this block type generates audio signals (has no audio inputs)
    public var isGenerator: Bool {
        return category == .generators
    }

    /// Whether this block type only processes audio (doesn't generate)
    public var isProcessor: Bool {
        return category == .processing
    }

    /// Whether this block type analyzes audio without passing it through
    public var isAnalyzer: Bool {
        return category == .analysis
    }

    /// Whether this block type outputs audio to devices
    public var isOutput: Bool {
        return category == .output
    }

    /// Required parameters that must be present for this block type
    public var requiredParameters: [String] {
        switch self {
        // Generators typically need frequency
        case .sineOscillator, .squareOscillator, .triangleOscillator, .sawtoothOscillator:
            return ["frequency"]

        case .whiteNoise, .pinkNoise:
            return ["amplitude"]

        case .linearChirp:
            return ["startFrequency", "endFrequency", "duration"]

        case .hyperbolicChirp:
            return ["startFrequency", "endFrequency", "bandwidth"]

        // Modulation blocks
        case .amplitudeModulator:
            return ["depth"]

        case .frequencyModulator:
            return ["deviation"]

        case .ringModulator:
            return [] // No required parameters, just multiplies inputs

        // Processing blocks
        case .lowPassFilter, .highPassFilter:
            return ["cutoffFrequency"]

        case .bandPassFilter:
            return ["centerFrequency", "qFactor"]

        case .mixer:
            return [] // Dynamic inputs, no fixed parameters

        case .amplifier:
            return ["gain"]

        // Analysis blocks
        case .spectrumAnalyzer:
            return ["windowSize", "overlap"]

        case .levelMeter:
            return ["timeConstant"]

        case .frequencyCounter:
            return ["sampleWindow"]

        // Output
        case .audioOutput:
            return [] // No parameters, just routes audio
        }
    }

    /// Default input ports for this block type
    public var defaultInputPorts: [InputPort] {
        switch self {
        // Generators typically have no inputs (except modulation inputs)
        case .sineOscillator, .squareOscillator, .triangleOscillator, .sawtoothOscillator:
            return [
                InputPort(name: "frequency", displayName: "Frequency", signalType: .frequency, isRequired: false, defaultValue: nil)
            ]

        case .whiteNoise, .pinkNoise:
            return [] // Pure generators

        case .linearChirp, .hyperbolicChirp:
            return [] // Parameter-driven generators

        // Modulation blocks need carriers and modulation signals
        case .amplitudeModulator:
            return [
                InputPort(name: "carrier", displayName: "Carrier", signalType: .audio, isRequired: true, defaultValue: nil),
                InputPort(name: "modulation", displayName: "Modulation", signalType: .control, isRequired: true, defaultValue: nil)
            ]

        case .frequencyModulator:
            return [
                InputPort(name: "carrier", displayName: "Carrier", signalType: .audio, isRequired: true, defaultValue: nil),
                InputPort(name: "modulation", displayName: "Modulation", signalType: .control, isRequired: true, defaultValue: nil)
            ]

        case .ringModulator:
            return [
                InputPort(name: "signal1", displayName: "Signal 1", signalType: .audio, isRequired: true, defaultValue: nil),
                InputPort(name: "signal2", displayName: "Signal 2", signalType: .audio, isRequired: true, defaultValue: nil)
            ]

        // Processing blocks need audio inputs
        case .lowPassFilter, .highPassFilter, .bandPassFilter, .amplifier:
            return [
                InputPort(name: "input", displayName: "Input", signalType: .audio, isRequired: true, defaultValue: nil)
            ]

        case .mixer:
            return [
                InputPort(name: "input1", displayName: "Input 1", signalType: .audio, isRequired: false, defaultValue: 0.0),
                InputPort(name: "input2", displayName: "Input 2", signalType: .audio, isRequired: false, defaultValue: 0.0),
                InputPort(name: "input3", displayName: "Input 3", signalType: .audio, isRequired: false, defaultValue: 0.0),
                InputPort(name: "input4", displayName: "Input 4", signalType: .audio, isRequired: false, defaultValue: 0.0)
            ]

        // Analysis blocks need audio inputs
        case .spectrumAnalyzer, .levelMeter, .frequencyCounter:
            return [
                InputPort(name: "input", displayName: "Input", signalType: .audio, isRequired: true, defaultValue: nil)
            ]

        // Output needs audio input
        case .audioOutput:
            return [
                InputPort(name: "input", displayName: "Input", signalType: .audio, isRequired: true, defaultValue: nil)
            ]
        }
    }

    /// Default output ports for this block type
    public var defaultOutputPorts: [OutputPort] {
        switch self {
        // Generators produce audio signals
        case .sineOscillator, .squareOscillator, .triangleOscillator, .sawtoothOscillator,
             .whiteNoise, .pinkNoise, .linearChirp, .hyperbolicChirp:
            return [
                OutputPort(name: "signal", displayName: "Signal", signalType: .audio, isRequired: false, defaultValue: nil)
            ]

        // Modulation blocks produce modulated audio
        case .amplitudeModulator, .frequencyModulator, .ringModulator:
            return [
                OutputPort(name: "output", displayName: "Output", signalType: .audio, isRequired: false, defaultValue: nil)
            ]

        // Processing blocks produce processed audio
        case .lowPassFilter, .highPassFilter, .bandPassFilter, .mixer, .amplifier:
            return [
                OutputPort(name: "output", displayName: "Output", signalType: .audio, isRequired: false, defaultValue: nil)
            ]

        // Analysis blocks may produce both visual and control outputs
        case .spectrumAnalyzer:
            return [
                OutputPort(name: "magnitude", displayName: "Magnitude", signalType: .control, isRequired: false, defaultValue: nil),
                OutputPort(name: "phase", displayName: "Phase", signalType: .control, isRequired: false, defaultValue: nil)
            ]

        case .levelMeter:
            return [
                OutputPort(name: "peak", displayName: "Peak", signalType: .control, isRequired: false, defaultValue: nil),
                OutputPort(name: "rms", displayName: "RMS", signalType: .control, isRequired: false, defaultValue: nil)
            ]

        case .frequencyCounter:
            return [
                OutputPort(name: "frequency", displayName: "Frequency", signalType: .frequency, isRequired: false, defaultValue: nil)
            ]

        // Output blocks don't produce signals
        case .audioOutput:
            return []
        }
    }

    /// Creates default parameters for this block type
    public func createDefaultParameters() -> [String: BlockParameter] {
        switch self {
        case .sineOscillator, .squareOscillator, .triangleOscillator, .sawtoothOscillator:
            return createOscillatorParameters()
        case .whiteNoise, .pinkNoise:
            return createNoiseParameters()
        case .linearChirp:
            return createLinearChirpParameters()
        case .hyperbolicChirp:
            return createHyperbolicChirpParameters()
        case .amplitudeModulator:
            return createAmplitudeModulatorParameters()
        case .frequencyModulator:
            return createFrequencyModulatorParameters()
        case .lowPassFilter, .highPassFilter:
            return createFilterParameters()
        case .bandPassFilter:
            return createBandPassFilterParameters()
        case .amplifier:
            return createAmplifierParameters()
        case .spectrumAnalyzer:
            return createSpectrumAnalyzerParameters()
        case .levelMeter:
            return createLevelMeterParameters()
        case .frequencyCounter:
            return createFrequencyCounterParameters()
        case .ringModulator, .mixer, .audioOutput:
            return [:]
        }
    }

    private func createOscillatorParameters() -> [String: BlockParameter] {
        return [
            "frequency": .frequency(value: 440.0),
            "amplitude": .amplitude(value: -6.0)
        ]
    }

    private func createNoiseParameters() -> [String: BlockParameter] {
        return [
            "amplitude": .amplitude(value: -12.0)
        ]
    }

    private func createLinearChirpParameters() -> [String: BlockParameter] {
        return [
            "startFrequency": .frequency(name: "startFrequency", displayName: "Start Frequency", value: 100.0),
            "endFrequency": .frequency(name: "endFrequency", displayName: "End Frequency", value: 1000.0),
            "duration": .time(name: "duration", displayName: "Duration", value: 1.0, minTime: 0.1, maxTime: 10.0)
        ]
    }

    private func createHyperbolicChirpParameters() -> [String: BlockParameter] {
        return [
            "startFrequency": .frequency(name: "startFrequency", displayName: "Start Frequency", value: 1000.0),
            "endFrequency": .frequency(name: "endFrequency", displayName: "End Frequency", value: 10000.0),
            "bandwidth": .frequency(name: "bandwidth", displayName: "Bandwidth", value: 5000.0)
        ]
    }

    private func createAmplitudeModulatorParameters() -> [String: BlockParameter] {
        return [
            "depth": .percentage(name: "depth", displayName: "Depth", value: 50.0)
        ]
    }

    private func createFrequencyModulatorParameters() -> [String: BlockParameter] {
        return [
            "deviation": .frequency(name: "deviation", displayName: "Deviation", value: 1000.0, maxHz: 10000.0)
        ]
    }

    private func createFilterParameters() -> [String: BlockParameter] {
        return [
            "cutoffFrequency": .frequency(name: "cutoffFrequency", displayName: "Cutoff", value: 1000.0),
            "resonance": BlockParameter(name: "resonance", displayName: "Resonance", value: 0.7, minimumValue: 0.1, maximumValue: 10.0, unit: "", stepSize: 0.1)
        ]
    }

    private func createBandPassFilterParameters() -> [String: BlockParameter] {
        return [
            "centerFrequency": .frequency(name: "centerFrequency", displayName: "Center", value: 1000.0),
            "qFactor": BlockParameter(name: "qFactor", displayName: "Q Factor", value: 1.0, minimumValue: 0.1, maximumValue: 100.0, unit: "", stepSize: 0.1)
        ]
    }

    private func createAmplifierParameters() -> [String: BlockParameter] {
        return [
            "gain": .amplitude(name: "gain", displayName: "Gain", value: 0.0, minDb: -60.0, maxDb: 20.0)
        ]
    }

    private func createSpectrumAnalyzerParameters() -> [String: BlockParameter] {
        return [
            "windowSize": BlockParameter(name: "windowSize", displayName: "Window Size", value: 1024, minimumValue: 256, maximumValue: 8192, unit: "samples", stepSize: 1),
            "overlap": .percentage(name: "overlap", displayName: "Overlap", value: 50.0)
        ]
    }

    private func createLevelMeterParameters() -> [String: BlockParameter] {
        return [
            "timeConstant": .time(name: "timeConstant", displayName: "Time Constant", value: 0.1, minTime: 0.01, maxTime: 1.0)
        ]
    }

    private func createFrequencyCounterParameters() -> [String: BlockParameter] {
        return [
            "sampleWindow": .time(name: "sampleWindow", displayName: "Sample Window", value: 0.1, minTime: 0.01, maxTime: 1.0)
        ]
    }
}
