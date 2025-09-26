import Foundation

/// Represents a complete saved arrangement of blocks and connections
/// This is the main data structure for saving/loading entire signal processing setups
public struct BlockConfiguration: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public let createdDate: Date
    public var modifiedDate: Date
    public var blocks: [SignalBlock]
    public var connections: [Connection]
    public let version: String
    public var metadata: [String: String]

    /// Creates a new BlockConfiguration
    /// - Parameters:
    ///   - id: Unique identifier for the configuration
    ///   - name: User-defined name for the configuration
    ///   - createdDate: When the configuration was created
    ///   - modifiedDate: When last modified
    ///   - blocks: All blocks in the configuration
    ///   - connections: All connections between blocks
    ///   - version: Configuration format version
    ///   - metadata: Additional user-defined properties
    public init(
        id: UUID = UUID(),
        name: String,
        createdDate: Date = Date(),
        modifiedDate: Date = Date(),
        blocks: [SignalBlock] = [],
        connections: [Connection] = [],
        version: String = "1.0",
        metadata: [String: String] = [:]
    ) {
        // Validate inputs
        precondition(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Configuration name cannot be empty")
        precondition(createdDate <= modifiedDate,
                    "Modified date must be >= created date")

        self.id = id
        self.name = name
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.blocks = blocks
        self.connections = connections
        self.version = version
        self.metadata = metadata

        // Validate the configuration after initialization
        self.validateConfiguration()
    }

    /// Creates an empty configuration with a default name
    public static func empty(name: String = "Untitled Configuration") -> BlockConfiguration {
        return BlockConfiguration(name: name)
    }

    /// Creates a configuration from existing blocks and connections
    /// - Parameters:
    ///   - name: Configuration name
    ///   - blocks: Existing blocks
    ///   - connections: Existing connections
    /// - Returns: Validated configuration
    /// - Throws: ConfigurationError if validation fails
    public static func create(
        name: String,
        blocks: [SignalBlock],
        connections: [Connection]
    ) throws -> BlockConfiguration {
        let config: BlockConfiguration = BlockConfiguration(
            name: name,
            blocks: blocks,
            connections: connections
        )

        try config.validateConnectionIntegrity()
        return config
    }

    /// Validates the configuration for consistency and integrity
    private func validateConfiguration() {
        // Validate that all block IDs are unique
        let blockIds: [UUID] = blocks.map { $0.id }
        precondition(blockIds.count == Set(blockIds).count,
                    "All block IDs must be unique within configuration")

        // Validate that all connection IDs are unique
        let connectionIds: [UUID] = connections.map { $0.id }
        precondition(connectionIds.count == Set(connectionIds).count,
                    "All connection IDs must be unique within configuration")

        // Basic referential integrity check
        for connection in connections {
            precondition(blocks.contains { $0.id == connection.sourceBlockId },
                        "Connection references non-existent source block: \(connection.sourceBlockId)")
            precondition(blocks.contains { $0.id == connection.destinationBlockId },
                        "Connection references non-existent destination block: \(connection.destinationBlockId)")
        }
    }

    /// Validates detailed connection integrity including port compatibility
    /// - Throws: ConfigurationError if validation fails
    public func validateConnectionIntegrity() throws {
        for connection in connections {
            guard let sourceBlock: SignalBlock = blocks.first(where: { $0.id == connection.sourceBlockId }) else {
                throw ConfigurationError.invalidConnection(
                    "Source block \(connection.sourceBlockId) not found for connection \(connection.id)"
                )
            }

            guard let destinationBlock: SignalBlock = blocks.first(where: { $0.id == connection.destinationBlockId }) else {
                throw ConfigurationError.invalidConnection(
                    "Destination block \(connection.destinationBlockId) not found for connection \(connection.id)"
                )
            }

            try connection.validate(from: sourceBlock, to: destinationBlock)
        }

        // Check for cycles
        if connections.hasCycle() {
            throw ConfigurationError.cyclicConnections("Configuration contains feedback loops")
        }

        // Validate input port constraints (one connection per input port)
        let portConflicts: [PortConflict] = connections.validateInputPortConstraints()
        if !portConflicts.isEmpty {
            let conflictDescription: String = portConflicts.map { "\($0.port) on block \($0.blockId)" }.joined(separator: ", ")
            throw ConfigurationError.inputPortConflicts("Multiple connections to ports: \(conflictDescription)")
        }
    }

    /// Adds a block to the configuration
    /// - Parameter block: The block to add
    /// - Returns: Updated configuration
    /// - Throws: ConfigurationError if block ID already exists
    public func addingBlock(_ block: SignalBlock) throws -> BlockConfiguration {
        guard !blocks.contains(where: { $0.id == block.id }) else {
            throw ConfigurationError.duplicateBlockId(block.id)
        }

        var updatedBlocks: [SignalBlock] = blocks
        updatedBlocks.append(block)

        return BlockConfiguration(
            id: id,
            name: name,
            createdDate: createdDate,
            modifiedDate: Date(),
            blocks: updatedBlocks,
            connections: connections,
            version: version,
            metadata: metadata
        )
    }

    /// Removes a block from the configuration
    /// Also removes all connections involving the block
    /// - Parameter blockId: ID of the block to remove
    /// - Returns: Updated configuration
    /// - Throws: ConfigurationError if block not found
    public func removingBlock(_ blockId: UUID) throws -> BlockConfiguration {
        guard blocks.contains(where: { $0.id == blockId }) else {
            throw ConfigurationError.blockNotFound(blockId)
        }

        let updatedBlocks: [SignalBlock] = blocks.filter { $0.id != blockId }
        let updatedConnections: [Connection] = connections.filter { !$0.involvesBlock(blockId) }

        return BlockConfiguration(
            id: id,
            name: name,
            createdDate: createdDate,
            modifiedDate: Date(),
            blocks: updatedBlocks,
            connections: updatedConnections,
            version: version,
            metadata: metadata
        )
    }

    /// Updates a block in the configuration
    /// - Parameter updatedBlock: The updated block
    /// - Returns: Updated configuration
    /// - Throws: ConfigurationError if block not found
    public func updatingBlock(_ updatedBlock: SignalBlock) throws -> BlockConfiguration {
        guard let index = blocks.firstIndex(where: { $0.id == updatedBlock.id }) else {
            throw ConfigurationError.blockNotFound(updatedBlock.id)
        }

        var updatedBlocks: [SignalBlock] = blocks
        updatedBlocks[index] = updatedBlock

        return BlockConfiguration(
            id: id,
            name: name,
            createdDate: createdDate,
            modifiedDate: Date(),
            blocks: updatedBlocks,
            connections: connections,
            version: version,
            metadata: metadata
        )
    }

    /// Adds a connection to the configuration
    /// - Parameter connection: The connection to add
    /// - Returns: Updated configuration
    /// - Throws: ConfigurationError if connection is invalid
    public func addingConnection(_ connection: Connection) throws -> BlockConfiguration {
        // Validate the connection
        guard let sourceBlock: SignalBlock = blocks.first(where: { $0.id == connection.sourceBlockId }) else {
            throw ConfigurationError.blockNotFound(connection.sourceBlockId)
        }

        guard let destinationBlock: SignalBlock = blocks.first(where: { $0.id == connection.destinationBlockId }) else {
            throw ConfigurationError.blockNotFound(connection.destinationBlockId)
        }

        try connection.validate(from: sourceBlock, to: destinationBlock)

        // Check if adding this connection would create a cycle
        if connections.wouldCreateCycle(adding: connection) {
            throw ConfigurationError.cyclicConnections("Adding connection would create a feedback loop")
        }

        // Check for input port conflicts
        let existingConnectionToPort: Connection? = connections.first { existingConnection in
            existingConnection.destinationBlockId == connection.destinationBlockId &&
            existingConnection.destinationPort == connection.destinationPort
        }

        if existingConnectionToPort != nil {
            throw ConfigurationError.inputPortConflicts(
                "Port \(connection.destinationPort) on block \(connection.destinationBlockId) already connected"
            )
        }

        var updatedConnections: [Connection] = connections
        updatedConnections.append(connection)

        return BlockConfiguration(
            id: id,
            name: name,
            createdDate: createdDate,
            modifiedDate: Date(),
            blocks: blocks,
            connections: updatedConnections,
            version: version,
            metadata: metadata
        )
    }

    /// Removes a connection from the configuration
    /// - Parameter connectionId: ID of the connection to remove
    /// - Returns: Updated configuration
    /// - Throws: ConfigurationError if connection not found
    public func removingConnection(_ connectionId: UUID) throws -> BlockConfiguration {
        guard connections.contains(where: { $0.id == connectionId }) else {
            throw ConfigurationError.connectionNotFound(connectionId)
        }

        let updatedConnections: [Connection] = connections.filter { $0.id != connectionId }

        return BlockConfiguration(
            id: id,
            name: name,
            createdDate: createdDate,
            modifiedDate: Date(),
            blocks: blocks,
            connections: updatedConnections,
            version: version,
            metadata: metadata
        )
    }

    /// Updates the configuration name
    /// - Parameter newName: New name for the configuration
    /// - Returns: Updated configuration
    public func renamingTo(_ newName: String) -> BlockConfiguration {
        return BlockConfiguration(
            id: id,
            name: newName,
            createdDate: createdDate,
            modifiedDate: Date(),
            blocks: blocks,
            connections: connections,
            version: version,
            metadata: metadata
        )
    }

    /// Updates metadata
    /// - Parameters:
    ///   - key: Metadata key
    ///   - value: Metadata value
    /// - Returns: Updated configuration
    public func settingMetadata(key: String, value: String) -> BlockConfiguration {
        var updatedMetadata: [String: String] = metadata
        updatedMetadata[key] = value

        return BlockConfiguration(
            id: id,
            name: name,
            createdDate: createdDate,
            modifiedDate: Date(),
            blocks: blocks,
            connections: connections,
            version: version,
            metadata: updatedMetadata
        )
    }

    /// Clears all blocks and connections
    /// - Returns: Empty configuration with same metadata
    public func cleared() -> BlockConfiguration {
        return BlockConfiguration(
            id: id,
            name: name,
            createdDate: createdDate,
            modifiedDate: Date(),
            blocks: [],
            connections: [],
            version: version,
            metadata: metadata
        )
    }

    /// Gets statistics about the configuration
    public var statistics: ConfigurationStatistics {
        let blocksByCategory: [BlockCategory: [SignalBlock]] = Dictionary(grouping: blocks, by: { $0.type.category })
        let connectionsByType: [SignalType: [Connection]] = Dictionary(grouping: connections, by: { $0.signalType })

        return ConfigurationStatistics(
            totalBlocks: blocks.count,
            totalConnections: connections.count,
            blocksByCategory: blocksByCategory.mapValues { $0.count },
            connectionsByType: connectionsByType.mapValues { $0.count },
            hasAudioOutput: blocks.contains { $0.type.isOutput },
            isValid: (try? validateConnectionIntegrity()) != nil
        )
    }

    /// Checks if the configuration is empty
    public var isEmpty: Bool {
        return blocks.isEmpty && connections.isEmpty
    }

    /// Gets the estimated file size for this configuration in bytes
    public var estimatedFileSize: Int {
        do {
            let data: Data = try JSONEncoder().encode(self)
            return data.count
        } catch {
            return 0
        }
    }

    /// Gets all blocks of a specific type
    /// - Parameter type: The block type to filter by
    /// - Returns: Array of blocks of the specified type
    public func blocks(ofType type: BlockType) -> [SignalBlock] {
        return blocks.filter { $0.type == type }
    }

    /// Gets all connections involving a specific block
    /// - Parameter blockId: ID of the block
    /// - Returns: Array of connections involving the block
    public func connections(involving blockId: UUID) -> [Connection] {
        return connections.connectionsInvolving(blockId)
    }

    /// Finds the shortest signal path between two blocks
    /// - Parameters:
    ///   - from: Source block ID
    ///   - to: Destination block ID
    /// - Returns: Array of block IDs representing the path, or nil if no path
    public func signalPath(from sourceBlockId: UUID, to destinationBlockId: UUID) -> [UUID]? {
        return connections.shortestPath(from: sourceBlockId, to: destinationBlockId)
    }
}

// MARK: - Configuration Statistics

/// Statistics about the configuration's structure and complexity
public struct ConfigurationStatistics {
    public let totalBlocks: Int
    public let totalConnections: Int
    public let blocksByCategory: [BlockCategory: Int]
    public let connectionsByType: [SignalType: Int]
    public let hasAudioOutput: Bool
    public let isValid: Bool

    /// Determines the complexity level based on total blocks
    public var complexity: ComplexityLevel {
        if totalBlocks <= 3 {
            return .simple
        } else if totalBlocks <= 10 {
            return .moderate
        } else if totalBlocks <= 20 {
            return .complex
        } else {
            return .veryComplex
        }
    }
}

public enum ComplexityLevel: String, CaseIterable {
    case simple
    case moderate
    case complex
    case veryComplex

    public var displayName: String {
        switch self {
        case .simple: return "Simple"
        case .moderate: return "Moderate"
        case .complex: return "Complex"
        case .veryComplex: return "Very Complex"
        }
    }
}

// MARK: - Configuration Errors

public enum ConfigurationError: Error, LocalizedError {
    case invalidConnection(String)
    case cyclicConnections(String)
    case inputPortConflicts(String)
    case duplicateBlockId(UUID)
    case blockNotFound(UUID)
    case connectionNotFound(UUID)
    case invalidFormat(String)
    case versionMismatch(found: String, expected: String)

    public var errorDescription: String? {
        switch self {
        case .invalidConnection(let message):
            return "Invalid connection: \(message)"
        case .cyclicConnections(let message):
            return "Cyclic connections: \(message)"
        case .inputPortConflicts(let message):
            return "Input port conflicts: \(message)"
        case .duplicateBlockId(let id):
            return "Duplicate block ID: \(id)"
        case .blockNotFound(let id):
            return "Block not found: \(id)"
        case .connectionNotFound(let id):
            return "Connection not found: \(id)"
        case .invalidFormat(let message):
            return "Invalid configuration format: \(message)"
        case .versionMismatch(let found, let expected):
            return "Version mismatch: found \(found), expected \(expected)"
        }
    }
}

// MARK: - JSON Persistence

extension BlockConfiguration {
    /// Loads a configuration from JSON data
    /// - Parameter data: JSON data containing the configuration
    /// - Returns: Decoded configuration
    /// - Throws: ConfigurationError if loading fails
    public static func fromJSON(_ data: Data) throws -> BlockConfiguration {
        do {
            let decoder: JSONDecoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let config: BlockConfiguration = try decoder.decode(BlockConfiguration.self, from: data)

            // Validate the loaded configuration
            try config.validateConnectionIntegrity()

            return config
        } catch let decodingError as DecodingError {
            throw ConfigurationError.invalidFormat("JSON decoding failed: \(decodingError.localizedDescription)")
        } catch let configError as ConfigurationError {
            throw configError
        } catch {
            throw ConfigurationError.invalidFormat("Unknown error: \(error.localizedDescription)")
        }
    }

    /// Loads a configuration from a JSON file
    /// - Parameter url: File URL containing the JSON configuration
    /// - Returns: Decoded configuration
    /// - Throws: ConfigurationError if loading fails
    public static func fromFile(_ url: URL) throws -> BlockConfiguration {
        do {
            let data: Data = try Data(contentsOf: url)
            return try fromJSON(data)
        } catch {
            throw ConfigurationError.invalidFormat("Failed to read file: \(error.localizedDescription)")
        }
    }

    /// Converts the configuration to JSON data
    /// - Returns: JSON data representation
    /// - Throws: ConfigurationError if encoding fails
    public func toJSON() throws -> Data {
        do {
            let encoder: JSONEncoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(self)
        } catch {
            throw ConfigurationError.invalidFormat("JSON encoding failed: \(error.localizedDescription)")
        }
    }

    /// Saves the configuration to a JSON file
    /// - Parameter url: File URL where to save the configuration
    /// - Throws: ConfigurationError if saving fails
    public func saveToFile(_ url: URL) throws {
        do {
            let data: Data = try toJSON()
            try data.write(to: url)
        } catch {
            throw ConfigurationError.invalidFormat("Failed to write file: \(error.localizedDescription)")
        }
    }
}