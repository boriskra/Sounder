import Foundation

/// Represents a signal path between two blocks
/// Connections define how audio and control signals flow through the block graph
public struct Connection: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public let sourceBlockId: UUID
    public let sourcePort: String
    public let destinationBlockId: UUID
    public let destinationPort: String
    public let signalType: SignalType
    public var isActive: Bool

    /// Creates a new Connection with validation
    /// - Parameters:
    ///   - id: Unique identifier for the connection
    ///   - sourceBlockId: ID of the block providing the signal
    ///   - sourcePort: Name of the output port
    ///   - destinationBlockId: ID of the block receiving the signal
    ///   - destinationPort: Name of the input port
    ///   - signalType: Type of signal being transmitted
    ///   - isActive: Whether signal is currently flowing
    public init(
        id: UUID = UUID(),
        sourceBlockId: UUID,
        sourcePort: String,
        destinationBlockId: UUID,
        destinationPort: String,
        signalType: SignalType,
        isActive: Bool = false
    ) {
        // Validate inputs
        precondition(sourceBlockId != destinationBlockId,
                    "Cannot connect block to itself")
        precondition(!sourcePort.isEmpty,
                    "Source port name cannot be empty")
        precondition(!destinationPort.isEmpty,
                    "Destination port name cannot be empty")

        self.id = id
        self.sourceBlockId = sourceBlockId
        self.sourcePort = sourcePort
        self.destinationBlockId = destinationBlockId
        self.destinationPort = destinationPort
        self.signalType = signalType
        self.isActive = isActive
    }

    /// Creates a connection with active state set to true
    /// - Parameters:
    ///   - sourceBlockId: ID of the source block
    ///   - sourcePort: Name of the output port
    ///   - destinationBlockId: ID of the destination block
    ///   - destinationPort: Name of the input port
    ///   - signalType: Type of signal being transmitted
    /// - Returns: Active connection
    public static func active(
        from sourceBlockId: UUID,
        sourcePort: String,
        to destinationBlockId: UUID,
        destinationPort: String,
        signalType: SignalType
    ) -> Connection {
        return Connection(
            sourceBlockId: sourceBlockId,
            sourcePort: sourcePort,
            destinationBlockId: destinationBlockId,
            destinationPort: destinationPort,
            signalType: signalType,
            isActive: true
        )
    }

    /// Updates the connection's active state
    /// - Parameter active: Whether the connection should be active
    /// - Returns: Updated Connection
    public func settingActive(_ active: Bool) -> Connection {
        return Connection(
            id: id,
            sourceBlockId: sourceBlockId,
            sourcePort: sourcePort,
            destinationBlockId: destinationBlockId,
            destinationPort: destinationPort,
            signalType: signalType,
            isActive: active
        )
    }

    /// Checks if this connection involves the specified block
    /// - Parameter blockId: ID of the block to check
    /// - Returns: True if the block is either source or destination
    public func involvesBlock(_ blockId: UUID) -> Bool {
        return sourceBlockId == blockId || destinationBlockId == blockId
    }

    /// Checks if this connection conflicts with another connection
    /// Two connections conflict if they connect to the same input port
    /// - Parameter other: Another connection to check against
    /// - Returns: True if the connections conflict
    public func conflictsWith(_ other: Connection) -> Bool {
        return destinationBlockId == other.destinationBlockId &&
               destinationPort == other.destinationPort
    }
}

/// Represents a conflict where multiple connections are attempting to connect to the same input port.
public struct PortConflict {
    /// The ID of the block where the conflict is occurring.
    public let blockId: UUID
    /// The name of the port with conflicting connections.
    public let port: String
    /// An array of the connections that are in conflict.
    public let conflicts: [Connection]
}

// MARK: - Cycle Detection

extension Array where Element == Connection {
    /// Detects if adding a new connection would create a feedback loop
    /// Uses depth-first search to detect cycles in the connection graph
    /// - Parameter newConnection: The connection to test
    /// - Returns: True if adding the connection would create a cycle
    public func wouldCreateCycle(adding newConnection: Connection) -> Bool {
        // Create a temporary graph including the new connection
        let allConnections: [Connection] = self + [newConnection]
        return allConnections.hasCycle()
    }

    /// Checks if the current set of connections contains any cycles
    /// - Returns: True if there are any feedback loops in the graph
    public func hasCycle() -> Bool {
        // Build adjacency list representation
        var graph: [UUID: Set<UUID>] = [:]
        var allBlocks: Set<UUID> = Set()

        for connection in self {
            allBlocks.insert(connection.sourceBlockId)
            allBlocks.insert(connection.destinationBlockId)

            if graph[connection.sourceBlockId] == nil {
                graph[connection.sourceBlockId] = Set()
            }
            graph[connection.sourceBlockId]?.insert(connection.destinationBlockId)
        }

        // Check for cycles using DFS from each node
        var visited: Set<UUID> = Set()
        var recursionStack: Set<UUID> = Set()

        for block in allBlocks where !visited.contains(block) {
            if hasCycleDFS(from: block, graph: graph, visited: &visited, recursionStack: &recursionStack) {
                return true
            }
        }

        return false
    }

    /// Depth-first search helper for cycle detection
    private func hasCycleDFS(
        from block: UUID,
        graph: [UUID: Set<UUID>],
        visited: inout Set<UUID>,
        recursionStack: inout Set<UUID>
    ) -> Bool {
        visited.insert(block)
        recursionStack.insert(block)

        if let neighbors = graph[block] {
            for neighbor in neighbors where !visited.contains(neighbor) {
                if hasCycleDFS(from: neighbor, graph: graph, visited: &visited, recursionStack: &recursionStack) {
                    return true
                }
            }
        }

        recursionStack.remove(block)
        return false
    }

    /// Gets all connections that involve a specific block
    /// - Parameter blockId: ID of the block
    /// - Returns: Array of connections involving the block
    public func connectionsInvolving(_ blockId: UUID) -> [Connection] {
        return filter { $0.involvesBlock(blockId) }
    }

    /// Gets all connections that originate from a specific block
    /// - Parameter blockId: ID of the source block
    /// - Returns: Array of outgoing connections
    public func connectionsFrom(_ blockId: UUID) -> [Connection] {
        return filter { $0.sourceBlockId == blockId }
    }

    /// Gets all connections that terminate at a specific block
    /// - Parameter blockId: ID of the destination block
    /// - Returns: Array of incoming connections
    public func connectionsTo(_ blockId: UUID) -> [Connection] {
        return filter { $0.destinationBlockId == blockId }
    }

    /// Gets all connections using a specific signal type
    /// - Parameter signalType: The signal type to filter by
    /// - Returns: Array of connections of the specified type
    public func connections(ofType signalType: SignalType) -> [Connection] {
        return filter { $0.signalType == signalType }
    }

    /// Validates that no input port has multiple connections
    /// Each input port should only receive one connection
    /// - Returns: Array of port conflicts (empty if valid)
    public func validateInputPortConstraints() -> [PortConflict] {
        var portConnections: [String: [Connection]] = [:]
        var conflicts: [PortConflict] = []

        // Group connections by destination port
        for connection in self {
            let portKey: String = "\(connection.destinationBlockId):\(connection.destinationPort)"
            if portConnections[portKey] == nil {
                portConnections[portKey] = []
            }
            portConnections[portKey]?.append(connection)
        }

        // Find ports with multiple connections
        for (portKey, connections) in portConnections where connections.count > 1 {
            let components: [String.SubSequence] = portKey.split(separator: ":")
            if components.count == 2,
               let blockId = UUID(uuidString: String(components[0])) {
                conflicts.append(PortConflict(
                    blockId: blockId,
                    port: String(components[1]),
                    conflicts: connections
                ))
            }
        }

        return conflicts
    }

    /// Finds the shortest path between two blocks through connections
    /// - Parameters:
    ///   - from: Source block ID
    ///   - to: Destination block ID
    /// - Returns: Array of block IDs representing the path, or nil if no path exists
    public func shortestPath(from sourceBlock: UUID, to destinationBlock: UUID) -> [UUID]? {
        guard sourceBlock != destinationBlock else { return [sourceBlock] }

        // Build adjacency list
        var graph: [UUID: Set<UUID>] = [:]
        for connection in self {
            if graph[connection.sourceBlockId] == nil {
                graph[connection.sourceBlockId] = Set()
            }
            graph[connection.sourceBlockId]?.insert(connection.destinationBlockId)
        }

        // BFS to find shortest path
        var queue: [(block: UUID, path: [UUID])] = [(sourceBlock, [sourceBlock])]
        var visited: Set<UUID> = [sourceBlock]

        while !queue.isEmpty {
            let (currentBlock, currentPath): (UUID, [UUID]) = queue.removeFirst()

            if let neighbors = graph[currentBlock] {
                for neighbor in neighbors {
                    if neighbor == destinationBlock {
                        return currentPath + [neighbor]
                    }

                    if !visited.contains(neighbor) {
                        visited.insert(neighbor)
                        queue.append((neighbor, currentPath + [neighbor]))
                    }
                }
            }
        }

        return nil // No path found
    }
}

extension Connection {
    /// Validates the connection against block port configurations
    /// - Parameters:
    ///   - sourceBlock: The source signal block
    ///   - destinationBlock: The destination signal block
    /// - Throws: ConnectionValidationError if connection is invalid
    public func validate(from sourceBlock: SignalBlock, to destinationBlock: SignalBlock) throws {
        // Check if source port exists
        guard sourceBlock.outputPort(named: sourcePort) != nil else {
            throw ConnectionValidationError.sourcePortNotFound(sourcePort, sourceBlock.type)
        }

        // Check if destination port exists
        guard destinationBlock.inputPort(named: destinationPort) != nil else {
            throw ConnectionValidationError.destinationPortNotFound(destinationPort, destinationBlock.type)
        }

        // Check signal type compatibility
        guard let sourceOutputPort = sourceBlock.outputPort(named: sourcePort),
              let destinationInputPort = destinationBlock.inputPort(named: destinationPort) else {
            // This should not happen if the previous guards passed
            return
        }

        guard sourceOutputPort.signalType.isCompatible(with: destinationInputPort.signalType) else {
            throw ConnectionValidationError.incompatibleSignalTypes(
                source: sourceOutputPort.signalType,
                destination: destinationInputPort.signalType
            )
        }
    }
}

// MARK: - Connection Validation Errors

public enum ConnectionValidationError: Error, LocalizedError {
    case sourcePortNotFound(String, BlockType)
    case destinationPortNotFound(String, BlockType)
    case incompatibleSignalTypes(source: SignalType, destination: SignalType)
    case selfConnection
    case cyclicConnection

    public var errorDescription: String? {
        switch self {
        case .sourcePortNotFound(let port, let blockType):
            return "Source port '\(port)' not found on \(blockType) block"
        case .destinationPortNotFound(let port, let blockType):
            return "Destination port '\(port)' not found on \(blockType) block"
        case .incompatibleSignalTypes(let source, let destination):
            return "Incompatible signal types: \(source) cannot connect to \(destination)"
        case .selfConnection:
            return "Cannot connect a block to itself"
        case .cyclicConnection:
            return "Connection would create a feedback loop"
        }
    }
}
