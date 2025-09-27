import Foundation

/// BlockConnection represents a connection between blocks for UI purposes
/// This is a simplified version of Connection used in views and serialization
public struct BlockConnection: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public let outputBlockId: UUID
    public let outputPort: String
    public let inputBlockId: UUID
    public let inputPort: String
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        outputBlockId: UUID,
        outputPort: String,
        inputBlockId: UUID,
        inputPort: String,
        isActive: Bool = true
    ) {
        self.id = id
        self.outputBlockId = outputBlockId
        self.outputPort = outputPort
        self.inputBlockId = inputBlockId
        self.inputPort = inputPort
        self.isActive = isActive
    }

    /// Converts this BlockConnection to a Connection model
    public func toConnection(signalType: SignalType = .audio) -> Connection {
        return Connection(
            id: id,
            sourceBlockId: outputBlockId,
            sourcePort: outputPort,
            destinationBlockId: inputBlockId,
            destinationPort: inputPort,
            signalType: signalType,
            isActive: isActive
        )
    }

    /// Creates a BlockConnection from a Connection model
    public init(from connection: Connection) {
        self.id = connection.id
        self.outputBlockId = connection.sourceBlockId
        self.outputPort = connection.sourcePort
        self.inputBlockId = connection.destinationBlockId
        self.inputPort = connection.destinationPort
        self.isActive = connection.isActive
    }
}

// MARK: - Convenience Extensions

extension Connection {
    /// Converts this Connection to a BlockConnection for UI use
    public func toBlockConnection() -> BlockConnection {
        return BlockConnection(from: self)
    }
}

extension Array where Element == BlockConnection {
    /// Converts an array of BlockConnections to Connections
    public func toConnections(defaultSignalType: SignalType = .audio) -> [Connection] {
        return map { $0.toConnection(signalType: defaultSignalType) }
    }
}

extension Array where Element == Connection {
    /// Converts an array of Connections to BlockConnections
    public func toBlockConnections() -> [BlockConnection] {
        return map { $0.toBlockConnection() }
    }
}
