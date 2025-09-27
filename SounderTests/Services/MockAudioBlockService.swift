import Foundation
import AVFoundation
import Combine
@testable import Sounder

/// Mock implementation of AudioBlockService for testing
public class MockAudioBlockService: AudioBlockService {
    private var isEngineRunning = false
    private var registeredBlocks: [UUID: SignalBlock] = [:]
    private var audioConnections: [MockAudioConnection] = []
    private var currentOutputDevice: OutputDevice?
    private var bufferUnderrunCount = 0
    private var cpuUsage: Double = 0.0

    // MARK: - Test Configuration

    public var shouldThrowError = false
    public var errorToThrow: AudioBlockError?
    public var mockOutputDevices: [OutputDevice] = []
    public var mockSpectrumData: [Float] = []
    public var mockLevelData: (peak: Float, rms: Float) = (0.0, 0.0)
    public var mockFrequencyAnalysis: Double?
    public var mockLatency: Double = 10.0

    public init() {
        // Set up default mock devices
        mockOutputDevices = [
            OutputDevice(id: "default", name: "Default Output", isDefault: true, isAvailable: true),
            OutputDevice(id: "builtin", name: "Built-in Speakers", isDefault: false, isAvailable: true),
            OutputDevice(id: "bluetooth", name: "Bluetooth Headphones", isDefault: false, isAvailable: true),
            OutputDevice(id: "airpods", name: "AirPods Pro", isDefault: false, isAvailable: false)
        ]

        // Set up default mock spectrum data
        mockSpectrumData = (0..<512).map { i in
            let frequency = Float(i) * 48000.0 / 512.0
            return 1.0 / (1.0 + frequency / 1000.0) // Simulate rolloff
        }

        mockLevelData = (peak: 0.5, rms: 0.3)
        mockFrequencyAnalysis = 440.0
    }

    // MARK: - Audio Engine Management

    public func initializeAudioEngine(sampleRate: Double, bufferSize: UInt32) async throws {
        if shouldThrowError {
            throw errorToThrow ?? AudioBlockError.audioEngineError("Mock initialization error")
        }

        guard sampleRate > 0 && bufferSize > 0 else {
            throw AudioBlockError.audioEngineError("Invalid sample rate or buffer size")
        }

        // Mock initialization success
    }

    public func startEngine() async throws {
        if shouldThrowError {
            throw errorToThrow ?? AudioBlockError.audioEngineError("Mock start error")
        }

        isEngineRunning = true
    }

    public func stopEngine() async {
        isEngineRunning = false

        // Reset all registered blocks
        for block in registeredBlocks.values {
            // Would reset audio state
        }
    }

    public func isEngineRunning() async -> Bool {
        return isEngineRunning
    }

    // MARK: - Block Audio Processing

    public func registerBlock(_ block: SignalBlock) async throws {
        if shouldThrowError {
            throw errorToThrow ?? AudioBlockError.blockRegistrationError("Mock registration error")
        }

        // Check for unsupported block types
        switch block.type {
        case .sineOscillator, .triangleOscillator, .audioOutput, .frequencyModulator, .amplifier, .whiteNoise, .spectrumAnalyzer:
            break // Supported
        default:
            throw AudioBlockError.blockRegistrationError("Unsupported block type: \(block.type)")
        }

        registeredBlocks[block.id] = block
    }

    public func unregisterBlock(id blockId: UUID) async {
        registeredBlocks.removeValue(forKey: blockId)

        // Remove all connections involving this block
        audioConnections.removeAll { connection in
            connection.sourceBlockId == blockId || connection.destinationBlockId == blockId
        }
    }

    public func updateBlockParameter(blockId: UUID, parameterName: String, value: Double) async throws {
        if shouldThrowError {
            throw errorToThrow ?? AudioBlockError.invalidParameterError("Mock parameter error")
        }

        guard registeredBlocks[blockId] != nil else {
            throw AudioBlockError.blockNotFoundError(blockId)
        }

        // Validate common parameters
        switch parameterName {
        case "frequency":
            guard value >= 20.0 && value <= 20000.0 else {
                throw AudioBlockError.invalidParameterError("Frequency out of range")
            }
        case "amplitude":
            guard value >= -60.0 && value <= 0.0 else {
                throw AudioBlockError.invalidParameterError("Amplitude out of range")
            }
        default:
            break
        }

        // Mock parameter update
    }

    public func connectBlocks(
        from sourceBlockId: UUID,
        sourcePort: String,
        to destinationBlockId: UUID,
        destinationPort: String
    ) async throws {
        if shouldThrowError {
            throw errorToThrow ?? AudioBlockError.connectionError("Mock connection error")
        }

        guard registeredBlocks[sourceBlockId] != nil else {
            throw AudioBlockError.blockNotFoundError(sourceBlockId)
        }

        guard registeredBlocks[destinationBlockId] != nil else {
            throw AudioBlockError.blockNotFoundError(destinationBlockId)
        }

        let connection = MockAudioConnection(
            sourceBlockId: sourceBlockId,
            sourcePort: sourcePort,
            destinationBlockId: destinationBlockId,
            destinationPort: destinationPort
        )

        audioConnections.append(connection)
    }

    public func disconnectBlocks(
        from sourceBlockId: UUID,
        sourcePort: String,
        to destinationBlockId: UUID,
        destinationPort: String
    ) async {
        audioConnections.removeAll { connection in
            connection.sourceBlockId == sourceBlockId &&
            connection.sourcePort == sourcePort &&
            connection.destinationBlockId == destinationBlockId &&
            connection.destinationPort == destinationPort
        }
    }

    // MARK: - Audio Device Management

    public func getAvailableOutputDevices() async -> [OutputDevice] {
        return mockOutputDevices
    }

    public func setOutputDevice(_ device: OutputDevice) async throws {
        if shouldThrowError {
            throw errorToThrow ?? AudioBlockError.audioDeviceError("Mock device error")
        }

        guard device.isAvailable else {
            throw AudioBlockError.audioDeviceError("Device '\(device.name)' is not available")
        }

        currentOutputDevice = device
    }

    public func getCurrentOutputDevice() async -> OutputDevice? {
        return currentOutputDevice
    }

    // MARK: - Audio Analysis

    public func getSpectrumData(for blockId: UUID?) async -> [Float] {
        return mockSpectrumData
    }

    public func getLevelMeterData(for blockId: UUID?) async -> (peak: Float, rms: Float) {
        return mockLevelData
    }

    public func getFrequencyAnalysis(for blockId: UUID) async -> Double? {
        return mockFrequencyAnalysis
    }

    // MARK: - Performance Monitoring

    public func getAudioCPUUsage() async -> Double {
        return cpuUsage
    }

    public func getBufferUnderrunCount() async -> Int {
        return bufferUnderrunCount
    }

    public func getAudioLatency() async -> Double {
        return mockLatency
    }

    // MARK: - Test Helpers

    public func reset() {
        isEngineRunning = false
        registeredBlocks.removeAll()
        audioConnections.removeAll()
        currentOutputDevice = nil
        bufferUnderrunCount = 0
        cpuUsage = 0.0
        shouldThrowError = false
        errorToThrow = nil
    }

    public func getRegisteredBlocks() -> [UUID: SignalBlock] {
        return registeredBlocks
    }

    public func getAudioConnections() -> [MockAudioConnection] {
        return audioConnections
    }

    public func simulateBufferUnderrun() {
        bufferUnderrunCount += 1
    }

    public func setCPUUsage(_ usage: Double) {
        cpuUsage = usage
    }

    public func setMockDevices(_ devices: [OutputDevice]) {
        mockOutputDevices = devices
    }

    public func setMockSpectrumData(_ data: [Float]) {
        mockSpectrumData = data
    }

    public func setMockLevelData(peak: Float, rms: Float) {
        mockLevelData = (peak: peak, rms: rms)
    }

    public func setMockFrequencyAnalysis(_ frequency: Double?) {
        mockFrequencyAnalysis = frequency
    }
}

// MARK: - Mock Audio Connection

public struct MockAudioConnection {
    public let sourceBlockId: UUID
    public let sourcePort: String
    public let destinationBlockId: UUID
    public let destinationPort: String

    public init(sourceBlockId: UUID, sourcePort: String, destinationBlockId: UUID, destinationPort: String) {
        self.sourceBlockId = sourceBlockId
        self.sourcePort = sourcePort
        self.destinationBlockId = destinationBlockId
        self.destinationPort = destinationPort
    }
}