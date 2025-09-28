import Foundation
import AVFoundation

/// Audio output block for routing signals to specific devices
/// Supports Bluetooth isolation and device-specific configuration
public class AudioOutputBlock: AudioBlock {
    public let id: UUID
    public let type: BlockType = .audioOutput
    public let inputPorts: [String] = ["input"]
    public let outputPorts: [String] = []

    // Device management
    private var outputDevice: OutputDevice?
    private var audioUnit: AVAudioUnit?
    private var audioPlayer: AVAudioPlayerNode?

    // Audio processing
    private let sampleRate: Double
    private var inputBuffer: [Float] = []
    private var outputGain: Double = 1.0

    // Performance monitoring
    private var sampleCount: UInt64 = 0
    private var bufferUnderruns: UInt64 = 0
    private var deviceSwitches: UInt64 = 0
    private var lastDeviceSwitch: Date?

    // Bluetooth-specific features
    private var bluetoothLatencyCompensation: Double = 0.0
    private var deviceSpecificProcessing: Bool = false

    public init(signalBlock: SignalBlock, sampleRate: Double = 48000.0) {
        self.id = signalBlock.id
        self.sampleRate = sampleRate

        // Initialize output gain from parameters
        if let gainParam = signalBlock.parameters["gain"] {
            outputGain = pow(10.0, gainParam.value / 20.0) // Convert dB to linear
        }

        setupDefaultAudioOutput()
    }

    // MARK: - AudioBlock Protocol

    public func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]] {
        // Time-coherent audio output processing
        return processAudio(inputs: inputs, frameCount: frameCount)
    }

    public func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]] {
        guard let audioInput = inputs["input"], audioInput.count >= frameCount else {
            // Handle buffer underrun
            bufferUnderruns += 1
            return [:] // Audio output doesn't produce output signals
        }

        // Process audio for output
        var processedAudio = audioInput

        // Apply device-specific processing
        if deviceSpecificProcessing {
            processedAudio = applyDeviceSpecificProcessing(processedAudio)
        }

        // Apply output gain
        if outputGain != 1.0 {
            processedAudio = processedAudio.map { Float(Double($0) * outputGain) }
        }

        // Apply Bluetooth latency compensation if needed
        if let device = outputDevice, device.isBluetoothDevice && bluetoothLatencyCompensation > 0 {
            processedAudio = applyLatencyCompensation(processedAudio)
        }

        // Send to audio output (in a real implementation)
        sendToAudioOutput(processedAudio)

        sampleCount += UInt64(frameCount)
        return [:] // Audio output consumes input but produces no output
    }

    public func setParameter(name: String, value: Double) {
        switch name {
        case "gain":
            let clampedDb = max(-60.0, min(20.0, value))
            outputGain = pow(10.0, clampedDb / 20.0)

        case "bluetoothLatencyCompensation":
            bluetoothLatencyCompensation = max(0.0, min(200.0, value)) // 0-200ms

        default:
            break
        }
    }

    public func reset(to startSample: UInt64, sampleRate: Double) {
        inputBuffer.removeAll()
        sampleCount = startSample
        bufferUnderruns = 0
        setupDefaultAudioOutput()
        print("🔊 [DEBUG] AudioOutputBlock.reset(to:) - Reset to sample \(startSample) at \(sampleRate)Hz")
    }

    public func reset() {
        reset(to: 0, sampleRate: 48000.0)
    }

    // MARK: - Device Management

    /// Sets the output device for audio routing
    public func setOutputDevice(_ device: OutputDevice) throws {
        guard device.isAvailable else {
            throw AudioOutputError.deviceNotAvailable(device.name)
        }

        // Configure device-specific settings
        let previousDevice = outputDevice
        outputDevice = device
        deviceSwitches += 1
        lastDeviceSwitch = Date()

        // Apply device-specific configuration
        configureForDevice(device, previousDevice: previousDevice)

        print("Audio output switched to: \(device.displayName)")
    }

    /// Gets the currently selected output device
    public func getCurrentDevice() -> OutputDevice? {
        return outputDevice
    }

    /// Configures audio processing for specific device types
    private func configureForDevice(_ device: OutputDevice, previousDevice: OutputDevice?) {
        deviceSpecificProcessing = false
        bluetoothLatencyCompensation = 0.0

        if device.isBluetoothDevice {
            // Configure for Bluetooth devices
            deviceSpecificProcessing = true
            bluetoothLatencyCompensation = 40.0 // Typical Bluetooth latency

            print("Configured for Bluetooth device: \(device.name)")
            print("- Enabled latency compensation: \(bluetoothLatencyCompensation)ms")
            print("- Enabled device-specific processing")
        } else {
            // Configure for wired/built-in devices
            bluetoothLatencyCompensation = 0.0
            print("Configured for wired device: \(device.name)")
        }

        // Handle device switching analytics
        if let previous = previousDevice {
            recordDeviceSwitch(from: previous, toDevice: device)
        }
    }

    // MARK: - Audio Processing

    /// Sets up default audio output configuration
    private func setupDefaultAudioOutput() {
        // In a real implementation, this would configure AVAudioEngine
        inputBuffer.reserveCapacity(Int(sampleRate / 10)) // 100ms buffer

        // Configure for default device
        let defaultDevice = OutputDevice(
            id: 0,
            name: "Default Output",
            isDefault: true,
            isAvailable: true
        )

        try? setOutputDevice(defaultDevice)
    }

    /// Applies device-specific audio processing
    private func applyDeviceSpecificProcessing(_ input: [Float]) -> [Float] {
        guard let device = outputDevice, deviceSpecificProcessing else {
            return input
        }

        var processed = input

        if device.isBluetoothDevice {
            // Apply Bluetooth-specific processing
            processed = applyBluetoothOptimization(processed)
        }

        return processed
    }

    /// Applies Bluetooth-specific audio optimization
    private func applyBluetoothOptimization(_ input: [Float]) -> [Float] {
        // Bluetooth optimization techniques:
        // 1. Slight compression to reduce dynamic range
        // 2. High-frequency pre-emphasis for codec artifacts
        // 3. Gentle limiting to prevent clipping

        return input.map { sample in
            // Gentle compression (simplified)
            let compressed = sample * 0.9

            // Ensure no clipping
            return max(-1.0, min(1.0, compressed))
        }
    }

    /// Applies latency compensation for Bluetooth devices
    private func applyLatencyCompensation(_ input: [Float]) -> [Float] {
        // In a real implementation, this would implement proper delay compensation
        // For this demo, we'll just return the input as-is
        return input
    }

    /// Sends processed audio to the actual output device
    private func sendToAudioOutput(_ audio: [Float]) {
        // In a real implementation, this would:
        // 1. Configure AVAudioEngine output
        // 2. Route to specific device
        // 3. Handle real-time constraints

        // For demo, we'll just validate the audio
        validateAudioOutput(audio)
    }

    /// Validates audio output for quality assurance
    private func validateAudioOutput(_ audio: [Float]) {
        for sample in audio {
            assert(sample.isFinite, "Invalid audio sample: \(sample)")
            assert(abs(sample) <= 1.0, "Audio sample exceeds bounds: \(sample)")
        }
    }

    // MARK: - Performance Monitoring

    /// Gets current performance statistics
    public func getPerformanceStats() -> AudioOutputStats {
        return AudioOutputStats(
            samplesProcessed: sampleCount,
            bufferUnderruns: bufferUnderruns,
            deviceSwitches: deviceSwitches,
            currentDevice: outputDevice?.name ?? "None",
            isBluetoothActive: outputDevice?.isBluetoothDevice ?? false,
            latencyCompensation: bluetoothLatencyCompensation,
            outputQuality: calculateOutputQuality()
        )
    }

    /// Calculates output quality metric
    private func calculateOutputQuality() -> Double {
        let underrunRate = Double(bufferUnderruns) / max(1.0, Double(sampleCount / 1000))
        let underrunQuality = max(0.0, 1.0 - underrunRate)

        let deviceQuality = outputDevice?.isAvailable == true ? 1.0 : 0.0

        return (underrunQuality + deviceQuality) / 2.0
    }

    /// Records device switch for analytics
    private func recordDeviceSwitch(from: OutputDevice, toDevice: OutputDevice) {
        print("Device switch recorded:")
        print("  From: \(from.displayName)")
        print("  To: \(toDevice.displayName)")
        print("  Switch count: \(deviceSwitches)")

        // In a real implementation, this could:
        // 1. Log to analytics system
        // 2. Track user preferences
        // 3. Monitor device reliability
    }

    // MARK: - Bluetooth Isolation Features

    /// Validates Bluetooth device isolation
    public func validateBluetoothIsolation() -> BluetoothIsolationCheck {
        guard let device = outputDevice else {
            return BluetoothIsolationCheck(
                isIsolated: false,
                deviceType: "None",
                systemAudioAffected: false,
                isolationQuality: 0.0,
                recommendations: ["No device selected"]
            )
        }

        let isIsolated = !device.isDefault && device.isBluetoothDevice
        let isolationQuality = isIsolated ? 1.0 : 0.5

        var recommendations: [String] = []
        if !isIsolated {
            recommendations.append("Select a non-default Bluetooth device for better isolation")
        }
        if device.isDefault {
            recommendations.append("Using default device may affect system audio")
        }

        return BluetoothIsolationCheck(
            isIsolated: isIsolated,
            deviceType: device.isBluetoothDevice ? "Bluetooth" : "Wired",
            systemAudioAffected: device.isDefault,
            isolationQuality: isolationQuality,
            recommendations: recommendations
        )
    }
}

// MARK: - Data Structures

public struct AudioOutputStats {
    public let samplesProcessed: UInt64
    public let bufferUnderruns: UInt64
    public let deviceSwitches: UInt64
    public let currentDevice: String
    public let isBluetoothActive: Bool
    public let latencyCompensation: Double
    public let outputQuality: Double
}

public struct BluetoothIsolationCheck {
    public let isIsolated: Bool
    public let deviceType: String
    public let systemAudioAffected: Bool
    public let isolationQuality: Double
    public let recommendations: [String]
}

// MARK: - Error Types

public enum AudioOutputError: Error, LocalizedError {
    case deviceNotAvailable(String)
    case configurationFailed(String)
    case bufferUnderrun
    case deviceSwitchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .deviceNotAvailable(let device):
            return "Audio device not available: \(device)"
        case .configurationFailed(let reason):
            return "Audio configuration failed: \(reason)"
        case .bufferUnderrun:
            return "Audio buffer underrun detected"
        case .deviceSwitchFailed(let reason):
            return "Device switch failed: \(reason)"
        }
    }
}

// MARK: - Factory Methods

extension AudioOutputBlock {
    /// Creates an audio output configured for Bluetooth testing
    public static func createBluetoothOutput() -> AudioOutputBlock {
        let signalBlock = SignalBlock(
            type: .audioOutput,
            title: "Bluetooth Output",
            position: CGPoint.zero,
            parameters: [
                "gain": BlockParameter.amplitude(value: 0.0),
                "bluetoothLatencyCompensation": BlockParameter(
                    name: "bluetoothLatencyCompensation",
                    displayName: "BT Latency Comp",
                    value: 40.0,
                    minimumValue: 0.0,
                    maximumValue: 200.0,
                    unit: "ms",
                    stepSize: 1.0
                )
            ],
            inputPorts: BlockType.audioOutput.defaultInputPorts,
            outputPorts: BlockType.audioOutput.defaultOutputPorts
        )

        return AudioOutputBlock(signalBlock: signalBlock)
    }
}
