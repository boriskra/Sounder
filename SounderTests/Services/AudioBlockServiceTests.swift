import XCTest
import AVFoundation
@testable import Sounder

/// Contract tests for AudioBlockService
/// These tests define the expected behavior of the AudioBlockService protocol
class AudioBlockServiceTests: XCTestCase {

    var audioBlockService: AudioBlockService!

    override func setUp() {
        super.setUp()
        // This will fail until implementation exists
        // audioBlockService = AudioBlockServiceImpl()
    }

    override func tearDown() {
        audioBlockService = nil
        super.tearDown()
    }

    // MARK: - Audio Engine Management Contract Tests

    func testInitializeAudioEngine_ValidParameters_InitializesSuccessfully() async throws {
        // Given
        let sampleRate: Double = 48000
        let bufferSize: UInt32 = 512

        // When
        try await audioBlockService.initializeAudioEngine(sampleRate: sampleRate, bufferSize: bufferSize)

        // Then
        // Engine should be initialized but not necessarily running
        // This test will fail until implementation exists
        XCTFail("AudioBlockService implementation not available")
    }

    func testInitializeAudioEngine_InvalidSampleRate_ThrowsError() async {
        // Given
        let invalidSampleRate: Double = 0
        let bufferSize: UInt32 = 512

        // When/Then
        do {
            try await audioBlockService.initializeAudioEngine(sampleRate: invalidSampleRate, bufferSize: bufferSize)
            XCTFail("Should throw error for invalid sample rate")
        } catch AudioBlockError.audioEngineError(let message) {
            XCTAssertTrue(message.contains("sample rate") || message.contains("invalid"))
        } catch {
            XCTFail("Should throw specific AudioEngineError")
        }
    }

    func testInitializeAudioEngine_InvalidBufferSize_ThrowsError() async {
        // Given
        let sampleRate: Double = 48000
        let invalidBufferSize: UInt32 = 0

        // When/Then
        do {
            try await audioBlockService.initializeAudioEngine(sampleRate: sampleRate, bufferSize: invalidBufferSize)
            XCTFail("Should throw error for invalid buffer size")
        } catch AudioBlockError.audioEngineError(let message) {
            XCTAssertTrue(message.contains("buffer") || message.contains("invalid"))
        } catch {
            XCTFail("Should throw specific AudioEngineError")
        }
    }

    func testStartEngine_AfterInitialization_StartsSuccessfully() async throws {
        // Given
        try await audioBlockService.initializeAudioEngine(sampleRate: 48000, bufferSize: 512)

        // When
        try await audioBlockService.startEngine()

        // Then
        let isRunning = await audioBlockService.isEngineRunning()
        XCTAssertTrue(isRunning)
    }

    func testStopEngine_WhenRunning_StopsSuccessfully() async throws {
        // Given
        try await audioBlockService.initializeAudioEngine(sampleRate: 48000, bufferSize: 512)
        try await audioBlockService.startEngine()

        // When
        await audioBlockService.stopEngine()

        // Then
        let isRunning = await audioBlockService.isEngineRunning()
        XCTAssertFalse(isRunning)
    }

    func testIsEngineRunning_InitialState_ReturnsFalse() async {
        // When
        let isRunning = await audioBlockService.isEngineRunning()

        // Then
        XCTAssertFalse(isRunning)
    }

    // MARK: - Block Registration Contract Tests

    func testRegisterBlock_ValidSineOscillator_RegistersSuccessfully() async throws {
        // Given
        let block = SignalBlock(
            id: UUID(),
            type: .sineOscillator,
            title: "440Hz Sine",
            position: CGPoint(x: 0, y: 0),
            parameters: [
                "frequency": BlockParameter(
                    name: "frequency",
                    displayName: "Frequency",
                    value: 440.0,
                    minimumValue: 20.0,
                    maximumValue: 20000.0,
                    unit: "Hz",
                    stepSize: 1.0,
                    isLogarithmic: true
                )
            ],
            inputPorts: [],
            outputPorts: [
                OutputPort(
                    name: "signal",
                    displayName: "Signal",
                    signalType: .audio,
                    isRequired: false,
                    defaultValue: nil
                )
            ],
            isActive: false
        )

        // When
        try await audioBlockService.registerBlock(block)

        // Then
        // Block should be registered in audio engine
        // This test will fail until implementation exists
        XCTFail("AudioBlockService implementation not available")
    }

    func testRegisterBlock_UnsupportedBlockType_ThrowsError() async throws {
        // Given
        let unsupportedBlock = SignalBlock(
            id: UUID(),
            type: .spectrumAnalyzer, // Assuming this might not be implemented first
            title: "Analyzer",
            position: CGPoint(x: 0, y: 0),
            parameters: [:],
            inputPorts: [],
            outputPorts: [],
            isActive: false
        )

        // When/Then
        do {
            try await audioBlockService.registerBlock(unsupportedBlock)
            XCTFail("Should throw error for unsupported block type")
        } catch AudioBlockError.blockRegistrationError(let message) {
            XCTAssertTrue(message.contains("unsupported") || message.contains("not implemented"))
        } catch {
            XCTFail("Should throw specific BlockRegistrationError")
        }
    }

    func testUnregisterBlock_RegisteredBlock_UnregistersSuccessfully() async throws {
        // Given
        let block = createTestSineBlock()
        try await audioBlockService.registerBlock(block)

        // When
        await audioBlockService.unregisterBlock(id: block.id)

        // Then
        // Block should be removed from audio engine
        // Subsequent operations on this block should fail or be ignored
    }

    func testUnregisterBlock_NonExistentBlock_DoesNotThrow() async {
        // Given
        let nonExistentId = UUID()

        // When/Then - should not throw error, just ignore
        await audioBlockService.unregisterBlock(id: nonExistentId)

        // Should complete without error
    }

    // MARK: - Real-time Parameter Updates Contract Tests

    func testUpdateBlockParameter_RegisteredBlock_UpdatesInRealTime() async throws {
        // Given
        let block = createTestSineBlock()
        try await audioBlockService.registerBlock(block)
        try await audioBlockService.initializeAudioEngine(sampleRate: 48000, bufferSize: 512)

        // When
        try await audioBlockService.updateBlockParameter(blockId: block.id, parameterName: "frequency", value: 880.0)

        // Then
        // Parameter should be updated in real-time without audio dropouts
        // This test will fail until implementation exists
        XCTFail("AudioBlockService implementation not available")
    }

    func testUpdateBlockParameter_NonExistentBlock_ThrowsError() async {
        // Given
        let nonExistentId = UUID()

        // When/Then
        do {
            try await audioBlockService.updateBlockParameter(blockId: nonExistentId, parameterName: "frequency", value: 440.0)
            XCTFail("Should throw error for non-existent block")
        } catch AudioBlockError.blockNotFoundError(let id) {
            XCTAssertEqual(id, nonExistentId)
        } catch {
            XCTFail("Should throw specific BlockNotFoundError")
        }
    }

    func testUpdateBlockParameter_InvalidParameter_ThrowsError() async throws {
        // Given
        let block = createTestSineBlock()
        try await audioBlockService.registerBlock(block)

        // When/Then
        do {
            try await audioBlockService.updateBlockParameter(blockId: block.id, parameterName: "invalidParam", value: 100.0)
            XCTFail("Should throw error for invalid parameter")
        } catch AudioBlockError.invalidParameterError(let message) {
            XCTAssertTrue(message.contains("invalidParam") || message.contains("not found"))
        } catch {
            XCTFail("Should throw specific InvalidParameterError")
        }
    }

    // MARK: - Audio Connection Contract Tests

    func testConnectBlocks_ValidAudioConnection_ConnectsSuccessfully() async throws {
        // Given
        let sineBlock = createTestSineBlock()
        let outputBlock = createTestOutputBlock()
        try await audioBlockService.registerBlock(sineBlock)
        try await audioBlockService.registerBlock(outputBlock)

        // When
        try await audioBlockService.connectBlocks(
            from: sineBlock.id, sourcePort: "signal",
            to: outputBlock.id, destinationPort: "input"
        )

        // Then
        // Audio routing should be established
        // This test will fail until implementation exists
        XCTFail("AudioBlockService implementation not available")
    }

    func testConnectBlocks_InvalidSourcePort_ThrowsError() async throws {
        // Given
        let sineBlock = createTestSineBlock()
        let outputBlock = createTestOutputBlock()
        try await audioBlockService.registerBlock(sineBlock)
        try await audioBlockService.registerBlock(outputBlock)

        // When/Then
        do {
            try await audioBlockService.connectBlocks(
                from: sineBlock.id, sourcePort: "invalidPort",
                to: outputBlock.id, destinationPort: "input"
            )
            XCTFail("Should throw error for invalid source port")
        } catch AudioBlockError.connectionError(let message) {
            XCTAssertTrue(message.contains("port") || message.contains("invalid"))
        } catch {
            XCTFail("Should throw specific ConnectionError")
        }
    }

    func testDisconnectBlocks_ExistingConnection_DisconnectsSuccessfully() async throws {
        // Given
        let sineBlock = createTestSineBlock()
        let outputBlock = createTestOutputBlock()
        try await audioBlockService.registerBlock(sineBlock)
        try await audioBlockService.registerBlock(outputBlock)
        try await audioBlockService.connectBlocks(
            from: sineBlock.id, sourcePort: "signal",
            to: outputBlock.id, destinationPort: "input"
        )

        // When
        await audioBlockService.disconnectBlocks(
            from: sineBlock.id, sourcePort: "signal",
            to: outputBlock.id, destinationPort: "input"
        )

        // Then
        // Audio routing should be removed
        // Should not throw error
    }

    // MARK: - Audio Device Management Contract Tests

    func testGetAvailableOutputDevices_SystemDevices_ReturnsDeviceList() async {
        // When
        let devices = await audioBlockService.getAvailableOutputDevices()

        // Then
        XCTAssertFalse(devices.isEmpty, "Should return at least one output device (default)")

        // Default device should be included
        let hasDefaultDevice = devices.contains { $0.isDefault }
        XCTAssertTrue(hasDefaultDevice, "Should include default output device")
    }

    func testSetOutputDevice_ValidDevice_SetsDevice() async throws {
        // Given
        let devices = await audioBlockService.getAvailableOutputDevices()
        guard let firstDevice = devices.first else {
            XCTFail("No output devices available for testing")
            return
        }

        // When
        try await audioBlockService.setOutputDevice(firstDevice)

        // Then
        let currentDevice = await audioBlockService.getCurrentOutputDevice()
        XCTAssertEqual(currentDevice?.id, firstDevice.id)
    }

    func testSetOutputDevice_InvalidDevice_ThrowsError() async {
        // Given
        let invalidDevice = OutputDevice(
            id: "invalid-device-id",
            name: "Non-existent Device",
            isDefault: false,
            isAvailable: false
        )

        // When/Then
        do {
            try await audioBlockService.setOutputDevice(invalidDevice)
            XCTFail("Should throw error for invalid device")
        } catch AudioBlockError.audioDeviceError(let message) {
            XCTAssertTrue(message.contains("invalid") || message.contains("not available"))
        } catch {
            XCTFail("Should throw specific AudioDeviceError")
        }
    }

    func testGetCurrentOutputDevice_NoDeviceSet_ReturnsNil() async {
        // When
        let currentDevice = await audioBlockService.getCurrentOutputDevice()

        // Then
        // Initially no device should be set
        XCTAssertNil(currentDevice)
    }

    // MARK: - Performance Monitoring Contract Tests

    func testGetAudioCPUUsage_DuringProcessing_ReturnsUsagePercentage() async throws {
        // Given
        try await audioBlockService.initializeAudioEngine(sampleRate: 48000, bufferSize: 512)
        try await audioBlockService.startEngine()

        // When
        let cpuUsage = await audioBlockService.getAudioCPUUsage()

        // Then
        XCTAssertGreaterThanOrEqual(cpuUsage, 0.0)
        XCTAssertLessThanOrEqual(cpuUsage, 1.0)
    }

    func testGetBufferUnderrunCount_InitialState_ReturnsZero() async {
        // When
        let underrunCount = await audioBlockService.getBufferUnderrunCount()

        // Then
        XCTAssertEqual(underrunCount, 0)
    }

    func testGetAudioLatency_WithValidEngine_ReturnsLatencyInMs() async throws {
        // Given
        try await audioBlockService.initializeAudioEngine(sampleRate: 48000, bufferSize: 512)

        // When
        let latency = await audioBlockService.getAudioLatency()

        // Then
        XCTAssertGreaterThan(latency, 0.0)
        XCTAssertLessThan(latency, 100.0) // Should be under 100ms
    }

    // MARK: - Helper Methods

    private func createTestSineBlock() -> SignalBlock {
        return SignalBlock(
            id: UUID(),
            type: .sineOscillator,
            title: "Test Sine",
            position: CGPoint(x: 0, y: 0),
            parameters: [
                "frequency": BlockParameter(
                    name: "frequency",
                    displayName: "Frequency",
                    value: 440.0,
                    minimumValue: 20.0,
                    maximumValue: 20000.0,
                    unit: "Hz",
                    stepSize: 1.0,
                    isLogarithmic: true
                )
            ],
            inputPorts: [],
            outputPorts: [
                OutputPort(
                    name: "signal",
                    displayName: "Signal",
                    signalType: .audio,
                    isRequired: false,
                    defaultValue: nil
                )
            ],
            isActive: false
        )
    }

    private func createTestOutputBlock() -> SignalBlock {
        return SignalBlock(
            id: UUID(),
            type: .audioOutput,
            title: "Audio Output",
            position: CGPoint(x: 300, y: 0),
            parameters: [:],
            inputPorts: [
                InputPort(
                    name: "input",
                    displayName: "Input",
                    signalType: .audio,
                    isRequired: true,
                    defaultValue: nil
                )
            ],
            outputPorts: [],
            isActive: false
        )
    }
}