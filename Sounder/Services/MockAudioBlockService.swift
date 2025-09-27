import Foundation
import Combine

/// Mock implementation of AudioBlockService for testing and previews
class MockAudioBlockService: AudioBlockService, ObservableObject {
    @Published var isEngineRunning = false
    @Published var currentOutputDevice: OutputDevice?

    private var registeredBlocks: [UUID: SignalBlock] = [:]
    private var connections: [Connection] = []

    // Mock devices
    private let mockDevices = [
        OutputDevice(id: "mock-builtin", name: "Mock Built-in Output", isDefault: true, isAvailable: true),
        OutputDevice(id: "mock-headphones", name: "Mock Headphones", isDefault: false, isAvailable: true)
    ]

    init() {
        currentOutputDevice = mockDevices.first
    }

    // MARK: - Audio Engine Management

    func initializeAudioEngine(sampleRate: Double, bufferSize: UInt32) async throws {
        // Mock implementation
    }

    func startEngine() async throws {
        isEngineRunning = true
    }

    func stopEngine() async {
        isEngineRunning = false
    }

    func isEngineRunning() async -> Bool {
        return isEngineRunning
    }

    // MARK: - Block Audio Processing

    func registerBlock(_ block: SignalBlock) async throws {
        registeredBlocks[block.id] = block
    }

    func unregisterBlock(id blockId: UUID) async {
        registeredBlocks.removeValue(forKey: blockId)
    }

    func updateBlockParameter(blockId: UUID, parameterName: String, value: Double) async throws {
        guard var block = registeredBlocks[blockId] else { return }

        if var parameter = block.parameters[parameterName] {
            parameter.value = value
            block.parameters[parameterName] = parameter
            registeredBlocks[blockId] = block
        }
    }

    func connectBlocks(from sourceBlockId: UUID, sourcePort: String, to destinationBlockId: UUID, destinationPort: String) async throws {
        let connection = Connection(
            sourceBlockId: sourceBlockId,
            sourcePort: sourcePort,
            destinationBlockId: destinationBlockId,
            destinationPort: destinationPort,
            signalType: .audio,
            isActive: true
        )
        connections.append(connection)
    }

    func disconnectBlocks(from sourceBlockId: UUID, sourcePort: String, to destinationBlockId: UUID, destinationPort: String) async {
        connections.removeAll { connection in
            connection.sourceBlockId == sourceBlockId &&
            connection.sourcePort == sourcePort &&
            connection.destinationBlockId == destinationBlockId &&
            connection.destinationPort == destinationPort
        }
    }

    // MARK: - Audio Device Management

    func getAvailableOutputDevices() async -> [OutputDevice] {
        return mockDevices
    }

    func setOutputDevice(_ device: OutputDevice) async throws {
        currentOutputDevice = device
    }

    func getCurrentOutputDevice() async -> OutputDevice? {
        return currentOutputDevice
    }

    // MARK: - Audio Analysis

    func getSpectrumData(for blockId: UUID?) async -> [Float] {
        // Generate mock spectrum data
        return (0..<256).map { _ in Float.random(in: 0...1) }
    }

    func getLevelMeterData(for blockId: UUID?) async -> (peak: Float, rms: Float) {
        return (peak: Float.random(in: 0...1), rms: Float.random(in: 0...0.7))
    }

    func getFrequencyAnalysis(for blockId: UUID) async -> Double? {
        return Double.random(in: 20...20000)
    }

    // MARK: - Performance Monitoring

    func getPerformanceMetrics() async -> AudioPerformanceMetrics {
        return AudioPerformanceMetrics(
            cpuUsage: Double.random(in: 0...1),
            memoryUsage: Int.random(in: 100000...1000000),
            bufferUnderruns: 0,
            latency: Double.random(in: 5...50),
            blocksProcessed: registeredBlocks.count
        )
    }

    func resetPerformanceCounters() async {
        // Mock implementation
    }

    func getAudioCPUUsage() async -> Double {
        return Double.random(in: 0.05...0.25) // 5-25% CPU usage
    }

    func getBufferUnderrunCount() async -> Int {
        return 0 // No underruns in mock
    }

    func getAudioLatency() async -> Double {
        return Double.random(in: 5...15) // 5-15ms latency
    }
}

// Mock performance metrics if not defined
struct AudioPerformanceMetrics {
    let cpuUsage: Double
    let memoryUsage: Int
    let bufferUnderruns: Int
    let latency: Double
    let blocksProcessed: Int
}
