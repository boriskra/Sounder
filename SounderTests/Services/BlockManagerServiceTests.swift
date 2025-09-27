import XCTest
@testable import Sounder

/// Contract tests for BlockManagerService
/// These tests define the expected behavior of the BlockManagerService protocol
class BlockManagerServiceTests: XCTestCase {

    var blockManagerService: BlockManagerService!

    override func setUp() {
        super.setUp()
        // This will fail until implementation exists
        // blockManagerService = BlockManagerServiceImpl()
    }

    override func tearDown() {
        blockManagerService = nil
        super.tearDown()
    }

    // MARK: - Block Management Contract Tests

    func testCreateBlock_ValidType_ReturnsSignalBlock() async throws {
        // Given
        let blockType = BlockType.sineOscillator
        let position = CGPoint(x: 100, y: 150)

        // When
        let block = try await blockManagerService.createBlock(type: blockType, at: position)

        // Then
        XCTAssertEqual(block.type, blockType)
        XCTAssertEqual(block.position, position)
        XCTAssertFalse(block.id.uuidString.isEmpty)
        XCTAssertFalse(block.parameters.isEmpty, "Block should have default parameters")
        XCTAssertFalse(block.isActive, "New blocks should be inactive by default")
    }

    func testCreateBlock_InvalidType_ThrowsError() async {
        // Given
        let position = CGPoint(x: 100, y: 150)

        // When/Then
        do {
            // This should fail when we have proper validation
            _ = try await blockManagerService.createBlock(type: BlockType.sineOscillator, at: position)
            XCTFail("Should throw error for invalid block creation scenario")
        } catch {
            // Expected behavior
        }
    }

    func testRemoveBlock_ExistingBlock_RemovesSuccessfully() async throws {
        // Given
        let block = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))

        // When
        try await blockManagerService.removeBlock(id: block.id)

        // Then
        // Should verify block is removed from current configuration
        let config = await blockManagerService.getCurrentConfiguration()
        XCTAssertFalse(config.blocks.contains { $0.id == block.id })
    }

    func testRemoveBlock_NonExistentBlock_ThrowsError() async {
        // Given
        let nonExistentId = UUID()

        // When/Then
        do {
            try await blockManagerService.removeBlock(id: nonExistentId)
            XCTFail("Should throw BlockNotFoundError")
        } catch BlockManagerError.blockNotFoundError(let id) {
            XCTAssertEqual(id, nonExistentId)
        } catch {
            XCTFail("Should throw specific BlockNotFoundError")
        }
    }

    func testMoveBlock_ValidPosition_UpdatesPosition() async throws {
        // Given
        let block = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let newPosition = CGPoint(x: 200, y: 300)

        // When
        try await blockManagerService.moveBlock(id: block.id, to: newPosition)

        // Then
        let config = await blockManagerService.getCurrentConfiguration()
        let updatedBlock = config.blocks.first { $0.id == block.id }
        XCTAssertEqual(updatedBlock?.position, newPosition)
    }

    func testUpdateBlockParameter_ValidParameter_UpdatesValue() async throws {
        // Given
        let block = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let parameterName = "frequency"
        let newValue = 880.0

        // When
        try await blockManagerService.updateBlockParameter(blockId: block.id, parameterName: parameterName, value: newValue)

        // Then
        let config = await blockManagerService.getCurrentConfiguration()
        let updatedBlock = config.blocks.first { $0.id == block.id }
        let parameter = updatedBlock?.parameters[parameterName]
        XCTAssertEqual(parameter?.value, newValue)
    }

    func testUpdateBlockParameter_InvalidParameter_ThrowsError() async throws {
        // Given
        let block = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let invalidParameterName = "nonExistentParameter"

        // When/Then
        do {
            try await blockManagerService.updateBlockParameter(blockId: block.id, parameterName: invalidParameterName, value: 100.0)
            XCTFail("Should throw ParameterNotFoundError")
        } catch BlockManagerError.parameterNotFoundError(let paramName) {
            XCTAssertEqual(paramName, invalidParameterName)
        } catch {
            XCTFail("Should throw specific ParameterNotFoundError")
        }
    }

    // MARK: - Connection Management Contract Tests

    func testCreateConnection_ValidPorts_ReturnsConnection() async throws {
        // Given
        let sourceBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let destBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 200, y: 0))

        // When
        let connection = try await blockManagerService.createConnection(
            from: sourceBlock.id,
            sourcePort: "signal",
            to: destBlock.id,
            destinationPort: "input"
        )

        // Then
        XCTAssertEqual(connection.sourceBlockId, sourceBlock.id)
        XCTAssertEqual(connection.destinationBlockId, destBlock.id)
        XCTAssertEqual(connection.sourcePort, "signal")
        XCTAssertEqual(connection.destinationPort, "input")
        XCTAssertFalse(connection.id.uuidString.isEmpty)
    }

    func testCreateConnection_FeedbackLoop_ThrowsError() async throws {
        // Given
        let block1 = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let block2 = try await blockManagerService.createBlock(type: .frequencyModulator, at: CGPoint(x: 200, y: 0))

        // Create initial connection
        _ = try await blockManagerService.createConnection(
            from: block1.id, sourcePort: "signal",
            to: block2.id, destinationPort: "carrier"
        )

        // When/Then - try to create feedback loop
        do {
            _ = try await blockManagerService.createConnection(
                from: block2.id, sourcePort: "output",
                to: block1.id, destinationPort: "frequency"
            )
            XCTFail("Should prevent feedback loops")
        } catch BlockManagerError.connectionError(let message) {
            XCTAssertTrue(message.contains("feedback") || message.contains("cycle"))
        } catch {
            XCTFail("Should throw specific ConnectionError about feedback")
        }
    }

    func testValidateConnection_CompatiblePorts_ReturnsTrue() async throws {
        // Given
        let sourceBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let destBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 200, y: 0))

        // When
        let isValid = await blockManagerService.validateConnection(
            from: sourceBlock.id, sourcePort: "signal",
            to: destBlock.id, destinationPort: "input"
        )

        // Then
        XCTAssertTrue(isValid)
    }

    func testValidateConnection_IncompatibleSignalTypes_ReturnsFalse() async throws {
        // Given
        let sourceBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let destBlock = try await blockManagerService.createBlock(type: .spectrumAnalyzer, at: CGPoint(x: 200, y: 0))

        // When - attempt incompatible connection
        let isValid = await blockManagerService.validateConnection(
            from: sourceBlock.id, sourcePort: "signal",
            to: destBlock.id, destinationPort: "trigger"  // incompatible signal type
        )

        // Then
        XCTAssertFalse(isValid)
    }

    // MARK: - Configuration Management Contract Tests

    func testGetCurrentConfiguration_EmptyCanvas_ReturnsEmptyConfig() async {
        // When
        let config = await blockManagerService.getCurrentConfiguration()

        // Then
        XCTAssertTrue(config.blocks.isEmpty)
        XCTAssertTrue(config.connections.isEmpty)
        XCTAssertFalse(config.id.uuidString.isEmpty)
        XCTAssertEqual(config.version, "1.0")
    }

    func testClearConfiguration_WithBlocks_RemovesAllBlocks() async throws {
        // Given
        _ = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        _ = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 200, y: 0))

        // When
        await blockManagerService.clearConfiguration()

        // Then
        let config = await blockManagerService.getCurrentConfiguration()
        XCTAssertTrue(config.blocks.isEmpty)
        XCTAssertTrue(config.connections.isEmpty)
    }
}