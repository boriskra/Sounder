import XCTest
@testable import Sounder

/// Specialized contract tests for BlockManagerService connection functionality
/// These tests focus specifically on the connection creation and validation behavior
class BlockManagerServiceContractTests: XCTestCase {

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

    // MARK: - Connection Creation Contract Tests

    func testCreateConnection_ValidAudioConnection_ReturnsActiveConnection() async throws {
        // Given
        let sineBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 300, y: 0))

        // When
        let connection = try await blockManagerService.createConnection(
            from: sineBlock.id,
            sourcePort: "signal",
            to: outputBlock.id,
            destinationPort: "input"
        )

        // Then
        XCTAssertEqual(connection.signalType, .audio)
        XCTAssertTrue(connection.isActive)
        XCTAssertNotNil(connection.id)

        // Verify connection appears in current configuration
        let config = await blockManagerService.getCurrentConfiguration()
        XCTAssertTrue(config.connections.contains { $0.id == connection.id })
    }

    func testCreateConnection_ValidControlConnection_ReturnsControlConnection() async throws {
        // Given
        let triangleBlock = try await blockManagerService.createBlock(type: .triangleOscillator, at: CGPoint(x: 0, y: 0))
        let fmBlock = try await blockManagerService.createBlock(type: .frequencyModulator, at: CGPoint(x: 200, y: 0))

        // When
        let connection = try await blockManagerService.createConnection(
            from: triangleBlock.id,
            sourcePort: "signal",
            to: fmBlock.id,
            destinationPort: "modulation"
        )

        // Then
        XCTAssertEqual(connection.signalType, .control)
        XCTAssertTrue(connection.isActive)
    }

    func testCreateConnection_PortAlreadyConnected_ThrowsError() async throws {
        // Given
        let sine1 = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let sine2 = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 100))
        let output = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 300, y: 0))

        // Create first connection
        _ = try await blockManagerService.createConnection(
            from: sine1.id, sourcePort: "signal",
            to: output.id, destinationPort: "input"
        )

        // When/Then - try to connect second source to same input port
        do {
            _ = try await blockManagerService.createConnection(
                from: sine2.id, sourcePort: "signal",
                to: output.id, destinationPort: "input"
            )
            XCTFail("Should not allow multiple connections to same input port")
        } catch BlockManagerError.connectionError(let message) {
            XCTAssertTrue(message.contains("already connected") || message.contains("occupied"))
        } catch {
            XCTFail("Should throw specific ConnectionError about port occupancy")
        }
    }

    func testCreateConnection_IncompatibleSignalTypes_ThrowsError() async throws {
        // Given
        let triggerBlock = try await blockManagerService.createBlock(type: .whiteNoise, at: CGPoint(x: 0, y: 0))
        let analyzerBlock = try await blockManagerService.createBlock(type: .spectrumAnalyzer, at: CGPoint(x: 200, y: 0))

        // When/Then - try to connect incompatible signal types
        do {
            _ = try await blockManagerService.createConnection(
                from: triggerBlock.id, sourcePort: "signal",  // audio signal
                to: analyzerBlock.id, destinationPort: "trigger"  // trigger signal expected
            )
            XCTFail("Should prevent incompatible signal type connections")
        } catch BlockManagerError.connectionError(let message) {
            XCTAssertTrue(message.contains("incompatible") || message.contains("signal type"))
        } catch {
            XCTFail("Should throw specific ConnectionError about signal type compatibility")
        }
    }

    func testCreateConnection_NonExistentSourceBlock_ThrowsError() async throws {
        // Given
        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 300, y: 0))
        let nonExistentId = UUID()

        // When/Then
        do {
            _ = try await blockManagerService.createConnection(
                from: nonExistentId, sourcePort: "signal",
                to: outputBlock.id, destinationPort: "input"
            )
            XCTFail("Should throw error for non-existent source block")
        } catch BlockManagerError.blockNotFoundError(let id) {
            XCTAssertEqual(id, nonExistentId)
        } catch {
            XCTFail("Should throw specific BlockNotFoundError")
        }
    }

    func testCreateConnection_NonExistentDestinationBlock_ThrowsError() async throws {
        // Given
        let sineBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let nonExistentId = UUID()

        // When/Then
        do {
            _ = try await blockManagerService.createConnection(
                from: sineBlock.id, sourcePort: "signal",
                to: nonExistentId, destinationPort: "input"
            )
            XCTFail("Should throw error for non-existent destination block")
        } catch BlockManagerError.blockNotFoundError(let id) {
            XCTAssertEqual(id, nonExistentId)
        } catch {
            XCTFail("Should throw specific BlockNotFoundError")
        }
    }

    func testCreateConnection_InvalidSourcePort_ThrowsError() async throws {
        // Given
        let sineBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 300, y: 0))

        // When/Then
        do {
            _ = try await blockManagerService.createConnection(
                from: sineBlock.id, sourcePort: "nonExistentPort",
                to: outputBlock.id, destinationPort: "input"
            )
            XCTFail("Should throw error for invalid source port")
        } catch BlockManagerError.connectionError(let message) {
            XCTAssertTrue(message.contains("port") && message.contains("nonExistentPort"))
        } catch {
            XCTFail("Should throw specific ConnectionError about invalid port")
        }
    }

    func testCreateConnection_InvalidDestinationPort_ThrowsError() async throws {
        // Given
        let sineBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 300, y: 0))

        // When/Then
        do {
            _ = try await blockManagerService.createConnection(
                from: sineBlock.id, sourcePort: "signal",
                to: outputBlock.id, destinationPort: "invalidPort"
            )
            XCTFail("Should throw error for invalid destination port")
        } catch BlockManagerError.connectionError(let message) {
            XCTAssertTrue(message.contains("port") && message.contains("invalidPort"))
        } catch {
            XCTFail("Should throw specific ConnectionError about invalid port")
        }
    }

    // MARK: - Connection Removal Contract Tests

    func testRemoveConnection_ExistingConnection_RemovesSuccessfully() async throws {
        // Given
        let sineBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 300, y: 0))
        let connection = try await blockManagerService.createConnection(
            from: sineBlock.id, sourcePort: "signal",
            to: outputBlock.id, destinationPort: "input"
        )

        // When
        try await blockManagerService.removeConnection(id: connection.id)

        // Then
        let config = await blockManagerService.getCurrentConfiguration()
        XCTAssertFalse(config.connections.contains { $0.id == connection.id })
    }

    func testRemoveConnection_NonExistentConnection_ThrowsError() async {
        // Given
        let nonExistentId = UUID()

        // When/Then
        do {
            try await blockManagerService.removeConnection(id: nonExistentId)
            XCTFail("Should throw ConnectionNotFoundError")
        } catch BlockManagerError.connectionNotFoundError(let id) {
            XCTAssertEqual(id, nonExistentId)
        } catch {
            XCTFail("Should throw specific ConnectionNotFoundError")
        }
    }

    // MARK: - Connection Validation Contract Tests

    func testValidateConnection_MultipleOutputsToSameBlock_ReturnsTrue() async throws {
        // Given
        let sineBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let mixerBlock = try await blockManagerService.createBlock(type: .mixer, at: CGPoint(x: 200, y: 0))

        // When - multiple outputs from same block should be allowed
        let valid1 = await blockManagerService.validateConnection(
            from: sineBlock.id, sourcePort: "signal",
            to: mixerBlock.id, destinationPort: "input1"
        )
        let valid2 = await blockManagerService.validateConnection(
            from: sineBlock.id, sourcePort: "signal",
            to: mixerBlock.id, destinationPort: "input2"
        )

        // Then
        XCTAssertTrue(valid1)
        XCTAssertTrue(valid2)
    }

    func testValidateConnection_CircularReference_ReturnsFalse() async throws {
        // Given
        let block1 = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let block2 = try await blockManagerService.createBlock(type: .frequencyModulator, at: CGPoint(x: 200, y: 0))
        let block3 = try await blockManagerService.createBlock(type: .amplifier, at: CGPoint(x: 400, y: 0))

        // Create chain: block1 -> block2 -> block3
        _ = try await blockManagerService.createConnection(
            from: block1.id, sourcePort: "signal",
            to: block2.id, destinationPort: "carrier"
        )
        _ = try await blockManagerService.createConnection(
            from: block2.id, sourcePort: "output",
            to: block3.id, destinationPort: "input"
        )

        // When - try to create circular reference: block3 -> block1
        let isValid = await blockManagerService.validateConnection(
            from: block3.id, sourcePort: "output",
            to: block1.id, destinationPort: "frequency"
        )

        // Then
        XCTAssertFalse(isValid, "Should detect and prevent circular references")
    }

    func testValidateConnection_SelfConnection_ReturnsFalse() async throws {
        // Given
        let block = try await blockManagerService.createBlock(type: .frequencyModulator, at: CGPoint(x: 0, y: 0))

        // When - try to connect block to itself
        let isValid = await blockManagerService.validateConnection(
            from: block.id, sourcePort: "output",
            to: block.id, destinationPort: "modulation"
        )

        // Then
        XCTAssertFalse(isValid, "Should prevent self-connections")
    }
}