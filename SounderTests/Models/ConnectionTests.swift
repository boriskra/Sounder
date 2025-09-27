import XCTest
import Foundation
@testable import Sounder

final class ConnectionTests: XCTestCase {

    // MARK: - Initialization Tests

    func testValidConnectionInitialization() {
        let sourceId = UUID()
        let destinationId = UUID()

        let connection = Connection(
            sourceBlockId: sourceId,
            sourcePort: "output",
            destinationBlockId: destinationId,
            destinationPort: "input",
            signalType: .audio,
            isActive: false
        )

        XCTAssertEqual(connection.sourceBlockId, sourceId)
        XCTAssertEqual(connection.sourcePort, "output")
        XCTAssertEqual(connection.destinationBlockId, destinationId)
        XCTAssertEqual(connection.destinationPort, "input")
        XCTAssertEqual(connection.signalType, .audio)
        XCTAssertFalse(connection.isActive)
    }

    func testSelfConnectionValidation() {
        let blockId = UUID()

        expectFatalError {
            _ = Connection(
                sourceBlockId: blockId,
                sourcePort: "output",
                destinationBlockId: blockId,
                destinationPort: "input",
                signalType: .audio
            )
        }
    }

    func testEmptySourcePortValidation() {
        expectFatalError {
            _ = Connection(
                sourceBlockId: UUID(),
                sourcePort: "",
                destinationBlockId: UUID(),
                destinationPort: "input",
                signalType: .audio
            )
        }
    }

    func testEmptyDestinationPortValidation() {
        expectFatalError {
            _ = Connection(
                sourceBlockId: UUID(),
                sourcePort: "output",
                destinationBlockId: UUID(),
                destinationPort: "",
                signalType: .audio
            )
        }
    }

    // MARK: - Active Connection Factory Tests

    func testActiveConnectionFactory() {
        let sourceId = UUID()
        let destinationId = UUID()

        let connection = Connection.active(
            from: sourceId,
            sourcePort: "signal",
            to: destinationId,
            destinationPort: "input",
            signalType: .audio
        )

        XCTAssertEqual(connection.sourceBlockId, sourceId)
        XCTAssertEqual(connection.sourcePort, "signal")
        XCTAssertEqual(connection.destinationBlockId, destinationId)
        XCTAssertEqual(connection.destinationPort, "input")
        XCTAssertEqual(connection.signalType, .audio)
        XCTAssertTrue(connection.isActive)
    }

    // MARK: - Active State Updates Tests

    func testSettingActive() {
        let connection = createValidConnection(isActive: false)
        let activeConnection = connection.settingActive(true)

        XCTAssertTrue(activeConnection.isActive)
        XCTAssertFalse(connection.isActive) // Original unchanged
        XCTAssertEqual(activeConnection.id, connection.id)
        XCTAssertEqual(activeConnection.sourceBlockId, connection.sourceBlockId)
        XCTAssertEqual(activeConnection.destinationBlockId, connection.destinationBlockId)
    }

    func testSettingInactive() {
        let connection = createValidConnection(isActive: true)
        let inactiveConnection = connection.settingActive(false)

        XCTAssertFalse(inactiveConnection.isActive)
        XCTAssertTrue(connection.isActive) // Original unchanged
    }

    // MARK: - Block Involvement Tests

    func testInvolvesBlock_SourceBlock() {
        let sourceId = UUID()
        let destinationId = UUID()
        let connection = createConnection(sourceId: sourceId, destinationId: destinationId)

        XCTAssertTrue(connection.involvesBlock(sourceId))
        XCTAssertFalse(connection.involvesBlock(UUID()))
    }

    func testInvolvesBlock_DestinationBlock() {
        let sourceId = UUID()
        let destinationId = UUID()
        let connection = createConnection(sourceId: sourceId, destinationId: destinationId)

        XCTAssertTrue(connection.involvesBlock(destinationId))
        XCTAssertFalse(connection.involvesBlock(UUID()))
    }

    func testInvolvesBlock_UnrelatedBlock() {
        let connection = createValidConnection()
        let unrelatedId = UUID()

        XCTAssertFalse(connection.involvesBlock(unrelatedId))
    }

    // MARK: - Connection Conflicts Tests

    func testConflictsWith_SameDestination() {
        let destinationId = UUID()
        let destinationPort = "input"

        let connection1 = createConnection(
            sourceId: UUID(),
            destinationId: destinationId,
            destinationPort: destinationPort
        )

        let connection2 = createConnection(
            sourceId: UUID(),
            destinationId: destinationId,
            destinationPort: destinationPort
        )

        XCTAssertTrue(connection1.conflictsWith(connection2))
        XCTAssertTrue(connection2.conflictsWith(connection1))
    }

    func testConflictsWith_DifferentDestinationBlocks() {
        let connection1 = createConnection(destinationId: UUID(), destinationPort: "input")
        let connection2 = createConnection(destinationId: UUID(), destinationPort: "input")

        XCTAssertFalse(connection1.conflictsWith(connection2))
    }

    func testConflictsWith_DifferentDestinationPorts() {
        let destinationId = UUID()
        let connection1 = createConnection(destinationId: destinationId, destinationPort: "input1")
        let connection2 = createConnection(destinationId: destinationId, destinationPort: "input2")

        XCTAssertFalse(connection1.conflictsWith(connection2))
    }

    func testConflictsWith_SameConnection() {
        let connection = createValidConnection()
        XCTAssertTrue(connection.conflictsWith(connection))
    }

    // MARK: - Simple Cycle Detection Tests

    func testHasCycle_NoCycle() {
        // A → B → C (linear chain)
        let blockA = UUID()
        let blockB = UUID()
        let blockC = UUID()

        let connections = [
            createConnection(sourceId: blockA, destinationId: blockB),
            createConnection(sourceId: blockB, destinationId: blockC)
        ]

        XCTAssertFalse(connections.hasCycle())
    }

    func testHasCycle_EmptyConnections() {
        let connections: [Connection] = []
        XCTAssertFalse(connections.hasCycle())
    }

    func testHasCycle_SingleConnection() {
        let connections = [createValidConnection()]
        XCTAssertFalse(connections.hasCycle())
    }

    func testHasCycle_SimpleCycle() {
        // A → B → A (simple cycle)
        let blockA = UUID()
        let blockB = UUID()

        let connections = [
            createConnection(sourceId: blockA, destinationId: blockB),
            createConnection(sourceId: blockB, destinationId: blockA)
        ]

        XCTAssertTrue(connections.hasCycle())
    }

    func testHasCycle_ThreeNodeCycle() {
        // A → B → C → A (three-node cycle)
        let blockA = UUID()
        let blockB = UUID()
        let blockC = UUID()

        let connections = [
            createConnection(sourceId: blockA, destinationId: blockB),
            createConnection(sourceId: blockB, destinationId: blockC),
            createConnection(sourceId: blockC, destinationId: blockA)
        ]

        XCTAssertTrue(connections.hasCycle())
    }

    func testHasCycle_ComplexCycle() {
        // A → B → C → D → B (cycle involving four nodes)
        let blockA = UUID()
        let blockB = UUID()
        let blockC = UUID()
        let blockD = UUID()

        let connections = [
            createConnection(sourceId: blockA, destinationId: blockB),
            createConnection(sourceId: blockB, destinationId: blockC),
            createConnection(sourceId: blockC, destinationId: blockD),
            createConnection(sourceId: blockD, destinationId: blockB)
        ]

        XCTAssertTrue(connections.hasCycle())
    }

    func testHasCycle_MultipleDisconnectedComponents() {
        // Component 1: A → B
        // Component 2: C → D
        let blockA = UUID()
        let blockB = UUID()
        let blockC = UUID()
        let blockD = UUID()

        let connections = [
            createConnection(sourceId: blockA, destinationId: blockB),
            createConnection(sourceId: blockC, destinationId: blockD)
        ]

        XCTAssertFalse(connections.hasCycle())
    }

    func testHasCycle_OneComponentWithCycle() {
        // Component 1: A → B (no cycle)
        // Component 2: C → D → C (cycle)
        let blockA = UUID()
        let blockB = UUID()
        let blockC = UUID()
        let blockD = UUID()

        let connections = [
            createConnection(sourceId: blockA, destinationId: blockB),
            createConnection(sourceId: blockC, destinationId: blockD),
            createConnection(sourceId: blockD, destinationId: blockC)
        ]

        XCTAssertTrue(connections.hasCycle())
    }

    func testHasCycle_ComplexGraphNoCycle() {
        // Diamond pattern: A → B, A → C, B → D, C → D
        let blockA = UUID()
        let blockB = UUID()
        let blockC = UUID()
        let blockD = UUID()

        let connections = [
            createConnection(sourceId: blockA, destinationId: blockB),
            createConnection(sourceId: blockA, destinationId: blockC),
            createConnection(sourceId: blockB, destinationId: blockD),
            createConnection(sourceId: blockC, destinationId: blockD)
        ]

        XCTAssertFalse(connections.hasCycle())
    }

    func testHasCycle_ComplexGraphWithCycle() {
        // Diamond with feedback: A → B, A → C, B → D, C → D, D → A
        let blockA = UUID()
        let blockB = UUID()
        let blockC = UUID()
        let blockD = UUID()

        let connections = [
            createConnection(sourceId: blockA, destinationId: blockB),
            createConnection(sourceId: blockA, destinationId: blockC),
            createConnection(sourceId: blockB, destinationId: blockD),
            createConnection(sourceId: blockC, destinationId: blockD),
            createConnection(sourceId: blockD, destinationId: blockA)
        ]

        XCTAssertTrue(connections.hasCycle())
    }

    // MARK: - Would Create Cycle Tests

    func testWouldCreateCycle_AddingNoCycle() {
        // Existing: A → B
        // Adding: B → C (should not create cycle)
        let blockA = UUID()
        let blockB = UUID()
        let blockC = UUID()

        let existingConnections = [
            createConnection(sourceId: blockA, destinationId: blockB)
        ]

        let newConnection = createConnection(sourceId: blockB, destinationId: blockC)

        XCTAssertFalse(existingConnections.wouldCreateCycle(adding: newConnection))
    }

    func testWouldCreateCycle_AddingSimpleCycle() {
        // Existing: A → B
        // Adding: B → A (would create cycle)
        let blockA = UUID()
        let blockB = UUID()

        let existingConnections = [
            createConnection(sourceId: blockA, destinationId: blockB)
        ]

        let newConnection = createConnection(sourceId: blockB, destinationId: blockA)

        XCTAssertTrue(existingConnections.wouldCreateCycle(adding: newConnection))
    }

    func testWouldCreateCycle_AddingLongCycle() {
        // Existing: A → B → C → D
        // Adding: D → A (would create long cycle)
        let blockA = UUID()
        let blockB = UUID()
        let blockC = UUID()
        let blockD = UUID()

        let existingConnections = [
            createConnection(sourceId: blockA, destinationId: blockB),
            createConnection(sourceId: blockB, destinationId: blockC),
            createConnection(sourceId: blockC, destinationId: blockD)
        ]

        let newConnection = createConnection(sourceId: blockD, destinationId: blockA)

        XCTAssertTrue(existingConnections.wouldCreateCycle(adding: newConnection))
    }

    func testWouldCreateCycle_AddingToEmptyConnections() {
        let emptyConnections: [Connection] = []
        let newConnection = createValidConnection()

        XCTAssertFalse(emptyConnections.wouldCreateCycle(adding: newConnection))
    }

    func testWouldCreateCycle_AddingIndependentConnection() {
        // Existing: A → B
        // Adding: C → D (independent, should not create cycle)
        let blockA = UUID()
        let blockB = UUID()
        let blockC = UUID()
        let blockD = UUID()

        let existingConnections = [
            createConnection(sourceId: blockA, destinationId: blockB)
        ]

        let newConnection = createConnection(sourceId: blockC, destinationId: blockD)

        XCTAssertFalse(existingConnections.wouldCreateCycle(adding: newConnection))
    }

    func testWouldCreateCycle_AddingBridgeConnection() {
        // Existing: A → B, C → D
        // Adding: B → C (bridge, should not create cycle)
        let blockA = UUID()
        let blockB = UUID()
        let blockC = UUID()
        let blockD = UUID()

        let existingConnections = [
            createConnection(sourceId: blockA, destinationId: blockB),
            createConnection(sourceId: blockC, destinationId: blockD)
        ]

        let newConnection = createConnection(sourceId: blockB, destinationId: blockC)

        XCTAssertFalse(existingConnections.wouldCreateCycle(adding: newConnection))
    }

    // MARK: - Connection Query Tests

    func testConnectionsInvolving() {
        let targetBlock = UUID()
        let otherBlock1 = UUID()
        let otherBlock2 = UUID()
        let unrelatedBlock = UUID()

        let connections = [
            createConnection(sourceId: targetBlock, destinationId: otherBlock1), // involves as source
            createConnection(sourceId: otherBlock2, destinationId: targetBlock), // involves as destination
            createConnection(sourceId: otherBlock1, destinationId: otherBlock2), // doesn't involve
            createConnection(sourceId: unrelatedBlock, destinationId: otherBlock1) // doesn't involve
        ]

        let involving = connections.connectionsInvolving(targetBlock)
        XCTAssertEqual(involving.count, 2)
        XCTAssertTrue(involving.allSatisfy { $0.involvesBlock(targetBlock) })
    }

    func testConnectionsFrom() {
        let sourceBlock = UUID()
        let otherBlock1 = UUID()
        let otherBlock2 = UUID()

        let connections = [
            createConnection(sourceId: sourceBlock, destinationId: otherBlock1),
            createConnection(sourceId: sourceBlock, destinationId: otherBlock2),
            createConnection(sourceId: otherBlock1, destinationId: otherBlock2)
        ]

        let fromSource = connections.connectionsFrom(sourceBlock)
        XCTAssertEqual(fromSource.count, 2)
        XCTAssertTrue(fromSource.allSatisfy { $0.sourceBlockId == sourceBlock })
    }

    func testConnectionsTo() {
        let destinationBlock = UUID()
        let otherBlock1 = UUID()
        let otherBlock2 = UUID()

        let connections = [
            createConnection(sourceId: otherBlock1, destinationId: destinationBlock),
            createConnection(sourceId: otherBlock2, destinationId: destinationBlock),
            createConnection(sourceId: otherBlock1, destinationId: otherBlock2)
        ]

        let toDestination = connections.connectionsTo(destinationBlock)
        XCTAssertEqual(toDestination.count, 2)
        XCTAssertTrue(toDestination.allSatisfy { $0.destinationBlockId == destinationBlock })
    }

    func testConnectionsOfType() {
        let connections = [
            createConnection(signalType: .audio),
            createConnection(signalType: .control),
            createConnection(signalType: .audio),
            createConnection(signalType: .frequency)
        ]

        let audioConnections = connections.connections(ofType: .audio)
        XCTAssertEqual(audioConnections.count, 2)
        XCTAssertTrue(audioConnections.allSatisfy { $0.signalType == .audio })

        let controlConnections = connections.connections(ofType: .control)
        XCTAssertEqual(controlConnections.count, 1)
        XCTAssertEqual(controlConnections.first?.signalType, .control)
    }

    // MARK: - Input Port Constraint Validation Tests

    func testValidateInputPortConstraints_NoConflicts() {
        let connections = [
            createConnection(destinationId: UUID(), destinationPort: "input1"),
            createConnection(destinationId: UUID(), destinationPort: "input2"),
            createConnection(destinationId: UUID(), destinationPort: "input3")
        ]

        let conflicts = connections.validateInputPortConstraints()
        XCTAssertTrue(conflicts.isEmpty)
    }

    func testValidateInputPortConstraints_SingleConflict() {
        let conflictingBlock = UUID()
        let conflictingPort = "input"

        let connections = [
            createConnection(sourceId: UUID(), destinationId: conflictingBlock, destinationPort: conflictingPort),
            createConnection(sourceId: UUID(), destinationId: conflictingBlock, destinationPort: conflictingPort),
            createConnection(destinationId: UUID(), destinationPort: "other_input")
        ]

        let conflicts = connections.validateInputPortConstraints()
        XCTAssertEqual(conflicts.count, 1)

        let conflict = conflicts.first!
        XCTAssertEqual(conflict.blockId, conflictingBlock)
        XCTAssertEqual(conflict.port, conflictingPort)
        XCTAssertEqual(conflict.conflicts.count, 2)
    }

    func testValidateInputPortConstraints_MultipleConflicts() {
        let block1 = UUID()
        let block2 = UUID()

        let connections = [
            createConnection(destinationId: block1, destinationPort: "input"),
            createConnection(destinationId: block1, destinationPort: "input"),
            createConnection(destinationId: block2, destinationPort: "main"),
            createConnection(destinationId: block2, destinationPort: "main"),
            createConnection(destinationId: block2, destinationPort: "main")
        ]

        let conflicts = connections.validateInputPortConstraints()
        XCTAssertEqual(conflicts.count, 2)

        let block1Conflict = conflicts.first { $0.blockId == block1 }
        XCTAssertNotNil(block1Conflict)
        XCTAssertEqual(block1Conflict?.conflicts.count, 2)

        let block2Conflict = conflicts.first { $0.blockId == block2 }
        XCTAssertNotNil(block2Conflict)
        XCTAssertEqual(block2Conflict?.conflicts.count, 3)
    }

    // MARK: - Shortest Path Tests

    func testShortestPath_DirectConnection() {
        let blockA = UUID()
        let blockB = UUID()

        let connections = [
            createConnection(sourceId: blockA, destinationId: blockB)
        ]

        let path = connections.shortestPath(from: blockA, to: blockB)
        XCTAssertEqual(path, [blockA, blockB])
    }

    func testShortestPath_SameBlock() {
        let block = UUID()
        let connections: [Connection] = []

        let path = connections.shortestPath(from: block, to: block)
        XCTAssertEqual(path, [block])
    }

    func testShortestPath_NoPath() {
        let blockA = UUID()
        let blockB = UUID()
        let blockC = UUID()
        let blockD = UUID()

        let connections = [
            createConnection(sourceId: blockA, destinationId: blockB),
            createConnection(sourceId: blockC, destinationId: blockD)
        ]

        let path = connections.shortestPath(from: blockA, to: blockC)
        XCTAssertNil(path)
    }

    func testShortestPath_LongerPath() {
        let blockA = UUID()
        let blockB = UUID()
        let blockC = UUID()
        let blockD = UUID()

        let connections = [
            createConnection(sourceId: blockA, destinationId: blockB),
            createConnection(sourceId: blockB, destinationId: blockC),
            createConnection(sourceId: blockC, destinationId: blockD)
        ]

        let path = connections.shortestPath(from: blockA, to: blockD)
        XCTAssertEqual(path, [blockA, blockB, blockC, blockD])
    }

    func testShortestPath_MultiplePaths() {
        // Diamond pattern: A has two paths to D (A→B→D and A→C→D)
        let blockA = UUID()
        let blockB = UUID()
        let blockC = UUID()
        let blockD = UUID()

        let connections = [
            createConnection(sourceId: blockA, destinationId: blockB),
            createConnection(sourceId: blockA, destinationId: blockC),
            createConnection(sourceId: blockB, destinationId: blockD),
            createConnection(sourceId: blockC, destinationId: blockD)
        ]

        let path = connections.shortestPath(from: blockA, to: blockD)
        XCTAssertEqual(path?.count, 3) // Should be length 3 for shortest path
        XCTAssertEqual(path?.first, blockA)
        XCTAssertEqual(path?.last, blockD)
    }

    // MARK: - Connection Validation Tests

    func testConnectionValidation_ValidConnection() throws {
        let sourceBlock = createValidSourceBlock()
        let destinationBlock = createValidDestinationBlock()

        let connection = Connection(
            sourceBlockId: sourceBlock.id,
            sourcePort: "signal",
            destinationBlockId: destinationBlock.id,
            destinationPort: "input",
            signalType: .audio
        )

        XCTAssertNoThrow(try connection.validate(from: sourceBlock, to: destinationBlock))
    }

    func testConnectionValidation_SourcePortNotFound() {
        let sourceBlock = createValidSourceBlock()
        let destinationBlock = createValidDestinationBlock()

        let connection = Connection(
            sourceBlockId: sourceBlock.id,
            sourcePort: "nonexistent",
            destinationBlockId: destinationBlock.id,
            destinationPort: "input",
            signalType: .audio
        )

        XCTAssertThrowsError(try connection.validate(from: sourceBlock, to: destinationBlock)) { error in
            guard case ConnectionValidationError.sourcePortNotFound(let port, let type) = error else {
                XCTFail("Expected sourcePortNotFound error")
                return
            }
            XCTAssertEqual(port, "nonexistent")
            XCTAssertEqual(type, sourceBlock.type)
        }
    }

    func testConnectionValidation_DestinationPortNotFound() {
        let sourceBlock = createValidSourceBlock()
        let destinationBlock = createValidDestinationBlock()

        let connection = Connection(
            sourceBlockId: sourceBlock.id,
            sourcePort: "signal",
            destinationBlockId: destinationBlock.id,
            destinationPort: "nonexistent",
            signalType: .audio
        )

        XCTAssertThrowsError(try connection.validate(from: sourceBlock, to: destinationBlock)) { error in
            guard case ConnectionValidationError.destinationPortNotFound(let port, let type) = error else {
                XCTFail("Expected destinationPortNotFound error")
                return
            }
            XCTAssertEqual(port, "nonexistent")
            XCTAssertEqual(type, destinationBlock.type)
        }
    }

    // MARK: - Equatable Tests

    func testEquality_IdenticalConnections() {
        let connection1 = createValidConnection()
        let connection2 = Connection(
            id: connection1.id,
            sourceBlockId: connection1.sourceBlockId,
            sourcePort: connection1.sourcePort,
            destinationBlockId: connection1.destinationBlockId,
            destinationPort: connection1.destinationPort,
            signalType: connection1.signalType,
            isActive: connection1.isActive
        )

        XCTAssertEqual(connection1, connection2)
    }

    func testEquality_DifferentIds() {
        let connection1 = createValidConnection()
        let connection2 = Connection(
            id: UUID(),
            sourceBlockId: connection1.sourceBlockId,
            sourcePort: connection1.sourcePort,
            destinationBlockId: connection1.destinationBlockId,
            destinationPort: connection1.destinationPort,
            signalType: connection1.signalType,
            isActive: connection1.isActive
        )

        XCTAssertNotEqual(connection1, connection2)
    }

    func testEquality_DifferentSignalTypes() {
        let connection1 = createConnection(signalType: .audio)
        let connection2 = Connection(
            id: connection1.id,
            sourceBlockId: connection1.sourceBlockId,
            sourcePort: connection1.sourcePort,
            destinationBlockId: connection1.destinationBlockId,
            destinationPort: connection1.destinationPort,
            signalType: .control,
            isActive: connection1.isActive
        )

        XCTAssertNotEqual(connection1, connection2)
    }

    // MARK: - Codable Tests

    func testCodable_EncodeDecode() throws {
        let originalConnection = createValidConnection()

        let encoder = JSONEncoder()
        let data = try encoder.encode(originalConnection)

        let decoder = JSONDecoder()
        let decodedConnection = try decoder.decode(Connection.self, from: data)

        XCTAssertEqual(originalConnection, decodedConnection)
    }

    // MARK: - Edge Cases and Stress Tests

    func testCycleDetection_LargeGraph() {
        // Create a large linear chain to test performance
        var connections: [Connection] = []
        var blocks: [UUID] = []

        for _ in 0..<100 {
            blocks.append(UUID())
        }

        for i in 0..<(blocks.count - 1) {
            connections.append(createConnection(sourceId: blocks[i], destinationId: blocks[i + 1]))
        }

        // Should not have cycle
        XCTAssertFalse(connections.hasCycle())

        // Add cycle at the end
        connections.append(createConnection(sourceId: blocks.last!, destinationId: blocks.first!))

        // Now should have cycle
        XCTAssertTrue(connections.hasCycle())
    }

    func testCycleDetection_MultipleCycles() {
        // Graph with multiple separate cycles
        let cycle1A = UUID()
        let cycle1B = UUID()
        let cycle2A = UUID()
        let cycle2B = UUID()

        let connections = [
            // First cycle: cycle1A → cycle1B → cycle1A
            createConnection(sourceId: cycle1A, destinationId: cycle1B),
            createConnection(sourceId: cycle1B, destinationId: cycle1A),
            // Second cycle: cycle2A → cycle2B → cycle2A
            createConnection(sourceId: cycle2A, destinationId: cycle2B),
            createConnection(sourceId: cycle2B, destinationId: cycle2A)
        ]

        XCTAssertTrue(connections.hasCycle())
    }

    func testCycleDetection_SelfLoop() {
        // Although precondition prevents this in init, test the algorithm
        let blockA = UUID()
        let blockB = UUID()

        // Create normal connections first
        var connections = [
            createConnection(sourceId: blockA, destinationId: blockB)
        ]

        // Manually create a connection that would be a self-loop
        // (bypassing validation for algorithm testing)
        let selfConnection = Connection(
            id: UUID(),
            sourceBlockId: blockA,
            sourcePort: "output",
            destinationBlockId: blockA,
            destinationPort: "input",
            signalType: .audio,
            isActive: false
        )

        // This would be prevented by validation, but test algorithm directly
        connections.append(selfConnection)
        XCTAssertTrue(connections.hasCycle())
    }

    // MARK: - Helper Methods

    private func createValidConnection(isActive: Bool = false) -> Connection {
        return Connection(
            sourceBlockId: UUID(),
            sourcePort: "output",
            destinationBlockId: UUID(),
            destinationPort: "input",
            signalType: .audio,
            isActive: isActive
        )
    }

    private func createConnection(
        sourceId: UUID = UUID(),
        destinationId: UUID = UUID(),
        sourcePort: String = "output",
        destinationPort: String = "input",
        signalType: SignalType = .audio
    ) -> Connection {
        return Connection(
            sourceBlockId: sourceId,
            sourcePort: sourcePort,
            destinationBlockId: destinationId,
            destinationPort: destinationPort,
            signalType: signalType
        )
    }

    private func createValidSourceBlock() -> SignalBlock {
        let outputPort = OutputPort(name: "signal", displayName: "Signal", signalType: .audio, isRequired: false, defaultValue: nil)
        let frequency = BlockParameter.frequency(value: 440.0)

        return SignalBlock(
            type: .sineOscillator,
            title: "Source",
            position: CGPoint(x: 0, y: 0),
            parameters: ["frequency": frequency],
            inputPorts: [],
            outputPorts: [outputPort],
            isActive: false
        )
    }

    private func createValidDestinationBlock() -> SignalBlock {
        let inputPort = InputPort(name: "input", displayName: "Input", signalType: .audio, isRequired: true, defaultValue: nil)
        let gain = BlockParameter.amplitude(name: "gain", displayName: "Gain", value: 0.0)

        return SignalBlock(
            type: .amplifier,
            title: "Destination",
            position: CGPoint(x: 100, y: 0),
            parameters: ["gain": gain],
            inputPorts: [inputPort],
            outputPorts: [],
            isActive: false
        )
    }

    private func expectFatalError(_ block: () -> Void) {
        // Note: In a real implementation, you would use a testing framework
        // that can capture fatal errors. For this example, we'll document
        // that these tests expect fatal errors.

        let expectation = XCTestExpectation(description: "Fatal error expected")
        expectation.isInverted = true

        DispatchQueue.global().async {
            block()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }
}