import XCTest
@testable import Sounder

/// Integration tests for basic block creation and connection workflow
/// These tests validate the complete user workflow from quickstart scenarios
class BlockWorkflowTests: XCTestCase {

    var blockManagerService: BlockManagerService!
    var audioBlockService: AudioBlockService!
    var blockCanvasService: BlockCanvasService!

    override func setUp() {
        super.setUp()
        // These will fail until implementations exist
        // blockManagerService = BlockManagerServiceImpl()
        // audioBlockService = AudioBlockServiceImpl()
        // blockCanvasService = BlockCanvasServiceImpl()
    }

    override func tearDown() {
        blockManagerService = nil
        audioBlockService = nil
        blockCanvasService = nil
        super.tearDown()
    }

    // MARK: - Test Scenario 1: Basic Block Creation and Connection (from quickstart.md)

    func testBasicWorkflow_CreateSineAndOutput_ConnectAndGenerateAudio() async throws {
        // Test Scenario 1 from quickstart.md: Basic Block Creation and Connection

        // Step 1: Launch application (verify services are available)
        XCTAssertNotNil(blockManagerService, "BlockManagerService should be available")
        XCTAssertNotNil(audioBlockService, "AudioBlockService should be available")
        XCTAssertNotNil(blockCanvasService, "BlockCanvasService should be available")

        // Verify empty canvas state
        let initialConfig = await blockManagerService.getCurrentConfiguration()
        XCTAssertTrue(initialConfig.blocks.isEmpty, "Canvas should start empty")
        XCTAssertTrue(initialConfig.connections.isEmpty, "Canvas should have no connections")

        // Step 2: Create Signal Generator Block (Sine Oscillator)
        let sineBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 100, y: 150))

        // Verify block creation
        XCTAssertEqual(sineBlock.type, .sineOscillator)
        XCTAssertEqual(sineBlock.position, CGPoint(x: 100, y: 150))
        XCTAssertFalse(sineBlock.isActive, "New blocks should be inactive")

        // Set frequency to 440 Hz
        try await blockManagerService.updateBlockParameter(blockId: sineBlock.id, parameterName: "frequency", value: 440.0)

        // Verify parameter update
        let configAfterUpdate = await blockManagerService.getCurrentConfiguration()
        let updatedSineBlock = configAfterUpdate.blocks.first { $0.id == sineBlock.id }
        let frequencyParam = updatedSineBlock?.parameters["frequency"]
        XCTAssertEqual(frequencyParam?.value, 440.0)
        XCTAssertEqual(frequencyParam?.unit, "Hz")

        // Step 3: Create Output Block
        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 400, y: 150))

        // Verify both blocks exist on canvas
        let configWithBothBlocks = await blockManagerService.getCurrentConfiguration()
        XCTAssertEqual(configWithBothBlocks.blocks.count, 2)

        // Step 4: Connect Blocks
        let connection = try await blockManagerService.createConnection(
            from: sineBlock.id,
            sourcePort: "signal",
            to: outputBlock.id,
            destinationPort: "input"
        )

        // Verify connection creation
        XCTAssertEqual(connection.sourceBlockId, sineBlock.id)
        XCTAssertEqual(connection.destinationBlockId, outputBlock.id)
        XCTAssertEqual(connection.sourcePort, "signal")
        XCTAssertEqual(connection.destinationPort, "input")
        XCTAssertEqual(connection.signalType, .audio)

        // Verify connection appears in configuration
        let finalConfig = await blockManagerService.getCurrentConfiguration()
        XCTAssertEqual(finalConfig.connections.count, 1)
        let storedConnection = finalConfig.connections.first
        XCTAssertEqual(storedConnection?.id, connection.id)

        // Step 5: Register blocks with audio engine
        try await audioBlockService.registerBlock(sineBlock)
        try await audioBlockService.registerBlock(outputBlock)

        // Step 6: Establish audio routing
        try await audioBlockService.connectBlocks(
            from: sineBlock.id, sourcePort: "signal",
            to: outputBlock.id, destinationPort: "input"
        )

        // Step 7: Test Audio Generation (prepare for playback)
        try await audioBlockService.initializeAudioEngine(sampleRate: 48000, bufferSize: 512)

        // Start audio processing
        try await blockManagerService.startAudioProcessing()

        // Verify audio processing state
        let isProcessing = await blockManagerService.isAudioProcessing()
        XCTAssertTrue(isProcessing, "Audio processing should be active")

        let isEngineRunning = await audioBlockService.isEngineRunning()
        XCTAssertTrue(isEngineRunning, "Audio engine should be running")

        // Stop audio processing
        await blockManagerService.stopAudioProcessing()

        let isStillProcessing = await blockManagerService.isAudioProcessing()
        XCTAssertFalse(isStillProcessing, "Audio processing should be stopped")

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected workflow")
    }

    func testWorkflow_MultipleBlockTypes_CreatesComplexChain() async throws {
        // Create a more complex signal chain: Triangle -> Frequency Modulator -> Amplifier -> Output

        // Create triangle oscillator (modulation source)
        let triangleBlock = try await blockManagerService.createBlock(type: .triangleOscillator, at: CGPoint(x: 0, y: 100))
        try await blockManagerService.updateBlockParameter(blockId: triangleBlock.id, parameterName: "frequency", value: 100.0)

        // Create frequency modulator
        let fmBlock = try await blockManagerService.createBlock(type: .frequencyModulator, at: CGPoint(x: 200, y: 100))
        try await blockManagerService.updateBlockParameter(blockId: fmBlock.id, parameterName: "deviation", value: 3000.0)

        // Create amplifier
        let ampBlock = try await blockManagerService.createBlock(type: .amplifier, at: CGPoint(x: 400, y: 100))
        try await blockManagerService.updateBlockParameter(blockId: ampBlock.id, parameterName: "gain", value: 0.8)

        // Create output
        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 600, y: 100))

        // Create connections
        let connection1 = try await blockManagerService.createConnection(
            from: triangleBlock.id, sourcePort: "signal",
            to: fmBlock.id, destinationPort: "modulation"
        )

        let connection2 = try await blockManagerService.createConnection(
            from: fmBlock.id, sourcePort: "output",
            to: ampBlock.id, destinationPort: "input"
        )

        let connection3 = try await blockManagerService.createConnection(
            from: ampBlock.id, sourcePort: "output",
            to: outputBlock.id, destinationPort: "input"
        )

        // Verify complete signal chain
        let config = await blockManagerService.getCurrentConfiguration()
        XCTAssertEqual(config.blocks.count, 4)
        XCTAssertEqual(config.connections.count, 3)

        // Verify connection signal types
        XCTAssertEqual(connection1.signalType, .control) // Modulation signal
        XCTAssertEqual(connection2.signalType, .audio)   // Audio signal
        XCTAssertEqual(connection3.signalType, .audio)   // Audio signal

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected complex workflow")
    }

    func testWorkflow_BlockRemoval_UpdatesConnections() async throws {
        // Create sine -> amplifier -> output chain
        let sineBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let ampBlock = try await blockManagerService.createBlock(type: .amplifier, at: CGPoint(x: 200, y: 0))
        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 400, y: 0))

        let connection1 = try await blockManagerService.createConnection(
            from: sineBlock.id, sourcePort: "signal",
            to: ampBlock.id, destinationPort: "input"
        )

        let connection2 = try await blockManagerService.createConnection(
            from: ampBlock.id, sourcePort: "output",
            to: outputBlock.id, destinationPort: "input"
        )

        // Verify initial state
        let configBefore = await blockManagerService.getCurrentConfiguration()
        XCTAssertEqual(configBefore.blocks.count, 3)
        XCTAssertEqual(configBefore.connections.count, 2)

        // Remove middle block (amplifier)
        try await blockManagerService.removeBlock(id: ampBlock.id)

        // Verify block and its connections are removed
        let configAfter = await blockManagerService.getCurrentConfiguration()
        XCTAssertEqual(configAfter.blocks.count, 2)

        // Both connections involving the removed block should be gone
        XCTAssertEqual(configAfter.connections.count, 0)

        // Remaining blocks should still exist
        let remainingBlockIds = Set(configAfter.blocks.map { $0.id })
        XCTAssertTrue(remainingBlockIds.contains(sineBlock.id))
        XCTAssertTrue(remainingBlockIds.contains(outputBlock.id))
        XCTAssertFalse(remainingBlockIds.contains(ampBlock.id))

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected removal workflow")
    }

    func testWorkflow_ParameterUpdates_ReflectInRealTime() async throws {
        // Create sine oscillator connected to output
        let sineBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 300, y: 0))

        let connection = try await blockManagerService.createConnection(
            from: sineBlock.id, sourcePort: "signal",
            to: outputBlock.id, destinationPort: "input"
        )

        // Register with audio engine
        try await audioBlockService.registerBlock(sineBlock)
        try await audioBlockService.registerBlock(outputBlock)
        try await audioBlockService.connectBlocks(
            from: sineBlock.id, sourcePort: "signal",
            to: outputBlock.id, destinationPort: "input"
        )

        // Start audio processing
        try await audioBlockService.initializeAudioEngine(sampleRate: 48000, bufferSize: 512)
        try await audioBlockService.startEngine()

        // Test parameter updates during playback
        let frequencies = [440.0, 880.0, 220.0, 440.0]

        for frequency in frequencies {
            // Update parameter in block manager
            try await blockManagerService.updateBlockParameter(
                blockId: sineBlock.id,
                parameterName: "frequency",
                value: frequency
            )

            // Update parameter in audio engine (real-time)
            try await audioBlockService.updateBlockParameter(
                blockId: sineBlock.id,
                parameterName: "frequency",
                value: frequency
            )

            // Verify parameter is updated in configuration
            let config = await blockManagerService.getCurrentConfiguration()
            let updatedBlock = config.blocks.first { $0.id == sineBlock.id }
            let param = updatedBlock?.parameters["frequency"]
            XCTAssertEqual(param?.value, frequency, "Parameter should be updated to \(frequency) Hz")

            // Small delay to simulate real-time updates
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        await audioBlockService.stopEngine()

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected parameter workflow")
    }

    func testWorkflow_FeedbackLoopPrevention_ThrowsError() async throws {
        // Create blocks that could form a feedback loop
        let block1 = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let block2 = try await blockManagerService.createBlock(type: .frequencyModulator, at: CGPoint(x: 200, y: 0))
        let block3 = try await blockManagerService.createBlock(type: .amplifier, at: CGPoint(x: 400, y: 0))

        // Create initial chain: block1 -> block2 -> block3
        _ = try await blockManagerService.createConnection(
            from: block1.id, sourcePort: "signal",
            to: block2.id, destinationPort: "carrier"
        )

        _ = try await blockManagerService.createConnection(
            from: block2.id, sourcePort: "output",
            to: block3.id, destinationPort: "input"
        )

        // Attempt to create feedback loop: block3 -> block1
        do {
            _ = try await blockManagerService.createConnection(
                from: block3.id, sourcePort: "output",
                to: block1.id, destinationPort: "frequency"
            )
            XCTFail("Should prevent feedback loops")
        } catch BlockManagerError.connectionError(let message) {
            XCTAssertTrue(message.contains("feedback") || message.contains("cycle") || message.contains("loop"))
        } catch {
            XCTFail("Should throw specific ConnectionError about feedback prevention")
        }

        // Verify no feedback loop was created
        let config = await blockManagerService.getCurrentConfiguration()
        XCTAssertEqual(config.connections.count, 2, "Should only have the two valid connections")

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected feedback prevention")
    }

    func testWorkflow_ConfigurationSaveLoad_PreservesWorkflow() async throws {
        // Create a complete workflow
        let sineBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 100, y: 100))
        let ampBlock = try await blockManagerService.createBlock(type: .amplifier, at: CGPoint(x: 300, y: 100))
        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 500, y: 100))

        // Set parameters
        try await blockManagerService.updateBlockParameter(blockId: sineBlock.id, parameterName: "frequency", value: 440.0)
        try await blockManagerService.updateBlockParameter(blockId: ampBlock.id, parameterName: "gain", value: 0.7)

        // Create connections
        let connection1 = try await blockManagerService.createConnection(
            from: sineBlock.id, sourcePort: "signal",
            to: ampBlock.id, destinationPort: "input"
        )

        let connection2 = try await blockManagerService.createConnection(
            from: ampBlock.id, sourcePort: "output",
            to: outputBlock.id, destinationPort: "input"
        )

        // Save configuration
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_workflow.json")
        try await blockManagerService.saveConfiguration(to: tempURL)

        // Clear current configuration
        await blockManagerService.clearConfiguration()

        let clearedConfig = await blockManagerService.getCurrentConfiguration()
        XCTAssertTrue(clearedConfig.blocks.isEmpty)
        XCTAssertTrue(clearedConfig.connections.isEmpty)

        // Load configuration
        let loadedConfig = try await blockManagerService.loadConfiguration(from: tempURL)

        // Verify workflow is restored
        XCTAssertEqual(loadedConfig.blocks.count, 3)
        XCTAssertEqual(loadedConfig.connections.count, 2)

        // Verify parameters are preserved
        let loadedSineBlock = loadedConfig.blocks.first { $0.type == .sineOscillator }
        let loadedFrequency = loadedSineBlock?.parameters["frequency"]?.value
        XCTAssertEqual(loadedFrequency, 440.0)

        let loadedAmpBlock = loadedConfig.blocks.first { $0.type == .amplifier }
        let loadedGain = loadedAmpBlock?.parameters["gain"]?.value
        XCTAssertEqual(loadedGain, 0.7)

        // Verify connections are preserved
        let loadedConnections = loadedConfig.connections
        let hasCorrectConnections = loadedConnections.allSatisfy { connection in
            let sourceExists = loadedConfig.blocks.contains { $0.id == connection.sourceBlockId }
            let destExists = loadedConfig.blocks.contains { $0.id == connection.destinationBlockId }
            return sourceExists && destExists
        }
        XCTAssertTrue(hasCorrectConnections)

        // Clean up
        try? FileManager.default.removeItem(at: tempURL)

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected save/load workflow")
    }
}