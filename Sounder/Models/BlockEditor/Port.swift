import Foundation

// MARK: - InputPort

/// Represents a connection point where a signal block can receive input signals
public struct InputPort: Codable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let name: String
    public let displayName: String
    public let signalType: SignalType
    public let isRequired: Bool
    public let defaultValue: Double?

    /// Creates a new InputPort
    /// - Parameters:
    ///   - id: Unique identifier for the port
    ///   - name: Port identifier used in connections
    ///   - displayName: Human-readable label for UI
    ///   - signalType: Type of signal this port accepts
    ///   - isRequired: Whether this port must be connected for the block to function
    ///   - defaultValue: Default value when no connection is present
    public init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        signalType: SignalType,
        isRequired: Bool = false,
        defaultValue: Double? = nil
    ) {
        precondition(!name.isEmpty, "Port name cannot be empty")
        precondition(!displayName.isEmpty, "Port display name cannot be empty")

        self.id = id
        self.name = name
        self.displayName = displayName
        self.signalType = signalType
        self.isRequired = isRequired
        self.defaultValue = defaultValue
    }

    /// Convenience initializer without explicit ID
    public init(
        name: String,
        displayName: String,
        signalType: SignalType,
        isRequired: Bool = false,
        defaultValue: Double? = nil
    ) {
        self.init(
            id: UUID(),
            name: name,
            displayName: displayName,
            signalType: signalType,
            isRequired: isRequired,
            defaultValue: defaultValue
        )
    }

    /// Checks if this port can accept a connection from the specified signal type
    /// - Parameter sourceSignalType: The signal type of the source port
    /// - Returns: True if the connection is valid
    public func canAccept(_ sourceSignalType: SignalType) -> Bool {
        return signalType.isCompatible(with: sourceSignalType)
    }

    /// Gets the effective value for this port given current connections
    /// - Parameter connections: Array of connections to check
    /// - Returns: The value from connection or default value
    public func effectiveValue(connections: [Connection]) -> Double? {
        // Check if this port has an active connection
        let incomingConnection: Connection? = connections.first { connection in
            connection.destinationPort == name && connection.isActive
        }

        if incomingConnection != nil {
            return nil // Value comes from connection
        } else {
            return defaultValue // Use default value
        }
    }

    /// Checks if this port is currently connected
    /// - Parameter connections: Array of connections to check
    /// - Returns: True if the port has an active connection
    public func isConnected(in connections: [Connection]) -> Bool {
        return connections.contains { connection in
            connection.destinationPort == name && connection.isActive
        }
    }

    /// Validates the port configuration
    /// - Throws: PortValidationError if configuration is invalid
    public func validate() throws {
        // Validate default value is within signal type range if provided
        if let defaultValue = defaultValue {
            let range: ClosedRange<Double> = signalType.valueRange
            guard defaultValue >= range.lowerBound && defaultValue <= range.upperBound else {
                throw PortValidationError.defaultValueOutOfRange(
                    port: name,
                    value: defaultValue,
                    range: range
                )
            }
        }

        // Validate that required ports either have connections or valid default values
        if isRequired && defaultValue == nil {
            throw PortValidationError.missingRequiredConnection(port: name)
        }
    }

    /// Gets the formatted display text for the port
    public var displayText: String {
        var text: String = displayName

        if let defaultValue = defaultValue {
            let formattedValue: String = signalType.formatValue(defaultValue)
            text += " (\(formattedValue))"
        }

        if isRequired {
            text += " *"
        }

        return text
    }

    /// Gets the visual position offset for this port on a block
    /// Used for UI rendering of connection points
    public func visualOffset(portIndex: Int, totalPorts: Int, blockHeight: CGFloat) -> CGPoint {
        let portSpacing: CGFloat = blockHeight / CGFloat(totalPorts + 1)
        let yOffset: CGFloat = portSpacing * CGFloat(portIndex + 1)
        return CGPoint(x: 0, y: yOffset) // Left side of block
    }
}

// MARK: - OutputPort

/// Represents a connection point where a signal block can provide output signals
public struct OutputPort: Codable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let name: String
    public let displayName: String
    public let signalType: SignalType
    public let isRequired: Bool
    public let defaultValue: Double?

    /// Creates a new OutputPort
    /// - Parameters:
    ///   - id: Unique identifier for the port
    ///   - name: Port identifier used in connections
    ///   - displayName: Human-readable label for UI
    ///   - signalType: Type of signal this port provides
    ///   - isRequired: Whether this port must be connected for the block to function properly
    ///   - defaultValue: Default value when port is not generating a signal
    public init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        signalType: SignalType,
        isRequired: Bool = false,
        defaultValue: Double? = nil
    ) {
        precondition(!name.isEmpty, "Port name cannot be empty")
        precondition(!displayName.isEmpty, "Port display name cannot be empty")

        self.id = id
        self.name = name
        self.displayName = displayName
        self.signalType = signalType
        self.isRequired = isRequired
        self.defaultValue = defaultValue
    }

    /// Convenience initializer without explicit ID
    public init(
        name: String,
        displayName: String,
        signalType: SignalType,
        isRequired: Bool = false,
        defaultValue: Double? = nil
    ) {
        self.init(
            id: UUID(),
            name: name,
            displayName: displayName,
            signalType: signalType,
            isRequired: isRequired,
            defaultValue: defaultValue
        )
    }

    /// Checks if this port can connect to the specified input signal type
    /// - Parameter destinationSignalType: The signal type of the destination port
    /// - Returns: True if the connection is valid
    public func canConnectTo(_ destinationSignalType: SignalType) -> Bool {
        return signalType.isCompatible(with: destinationSignalType)
    }

    /// Gets all outgoing connections from this port
    /// - Parameter connections: Array of connections to check
    /// - Returns: Array of connections originating from this port
    public func outgoingConnections(in connections: [Connection]) -> [Connection] {
        return connections.filter { connection in
            connection.sourcePort == name && connection.isActive
        }
    }

    /// Checks if this port is currently connected to any inputs
    /// - Parameter connections: Array of connections to check
    /// - Returns: True if the port has at least one active connection
    public func isConnected(in connections: [Connection]) -> Bool {
        return !outgoingConnections(in: connections).isEmpty
    }

    /// Gets the number of connections from this output port
    /// - Parameter connections: Array of connections to check
    /// - Returns: Number of active outgoing connections
    public func connectionCount(in connections: [Connection]) -> Int {
        return outgoingConnections(in: connections).count
    }

    /// Validates the port configuration
    /// - Throws: PortValidationError if configuration is invalid
    public func validate() throws {
        // Validate default value is within signal type range if provided
        if let defaultValue = defaultValue {
            let range: ClosedRange<Double> = signalType.valueRange
            guard defaultValue >= range.lowerBound && defaultValue <= range.upperBound else {
                throw PortValidationError.defaultValueOutOfRange(
                    port: name,
                    value: defaultValue,
                    range: range
                )
            }
        }
    }

    /// Gets formatted display text for the port
    public var displayText: String {
        var text: String = displayName

        if let defaultValue = defaultValue {
            let formattedValue: String = signalType.formatValue(defaultValue)
            text += " (\(formattedValue))"
        }

        if isRequired {
            text += " *"
        }

        return text
    }

    /// Gets the visual position offset for this port on a block
    /// Used for UI rendering of connection points
    public func visualOffset(portIndex: Int, totalPorts: Int, blockWidth: CGFloat, blockHeight: CGFloat) -> CGPoint {
        let portSpacing: CGFloat = blockHeight / CGFloat(totalPorts + 1)
        let yOffset: CGFloat = portSpacing * CGFloat(portIndex + 1)
        return CGPoint(x: blockWidth, y: yOffset) // Right side of block
    }
}

// MARK: - Port Validation Errors

public enum PortValidationError: Error, LocalizedError {
    case defaultValueOutOfRange(port: String, value: Double, range: ClosedRange<Double>)
    case incompatibleSignalTypes(source: SignalType, destination: SignalType)
    case missingRequiredConnection(port: String)
    case duplicatePortName(String)

    public var errorDescription: String? {
        switch self {
        case .defaultValueOutOfRange(let port, let value, let range):
            return "Port '\(port)' default value \(value) is outside valid range \(range)"
        case .incompatibleSignalTypes(let source, let destination):
            return "Cannot connect \(source.displayName) to \(destination.displayName)"
        case .missingRequiredConnection(let port):
            return "Required port '\(port)' must be connected"
        case .duplicatePortName(let name):
            return "Duplicate port name: '\(name)'"
        }
    }
}

// MARK: - Port Collections

extension Array where Element == InputPort {
    /// Validates that all port names are unique
    /// - Throws: PortValidationError if duplicate names are found
    public func validateUniqueNames() throws {
        let names: [String] = map { $0.name }
        let uniqueNames: Set<String> = Set(names)

        if names.count != uniqueNames.count {
            let duplicates: [String] = names.filter { name in
                names.filter { $0 == name }.count > 1
            }
            throw PortValidationError.duplicatePortName(duplicates.first ?? "unknown")
        }
    }

    /// Gets all required input ports
    public var requiredPorts: [InputPort] {
        return filter { $0.isRequired }
    }

    /// Gets all optional input ports
    public var optionalPorts: [InputPort] {
        return filter { !$0.isRequired }
    }

    /// Finds a port by name
    /// - Parameter name: The port name to search for
    /// - Returns: The port if found, nil otherwise
    public func port(named name: String) -> InputPort? {
        return first { $0.name == name }
    }

    /// Gets all ports that can accept the specified signal type
    /// - Parameter signalType: The signal type to check compatibility with
    /// - Returns: Array of compatible input ports
    public func compatiblePorts(for signalType: SignalType) -> [InputPort] {
        return filter { $0.canAccept(signalType) }
    }
}

extension Array where Element == OutputPort {
    /// Validates that all port names are unique
    /// - Throws: PortValidationError if duplicate names are found
    public func validateUniqueNames() throws {
        let names: [String] = map { $0.name }
        let uniqueNames: Set<String> = Set(names)

        if names.count != uniqueNames.count {
            let duplicates: [String] = names.filter { name in
                names.filter { $0 == name }.count > 1
            }
            throw PortValidationError.duplicatePortName(duplicates.first ?? "unknown")
        }
    }

    /// Gets all required output ports
    public var requiredPorts: [OutputPort] {
        return filter { $0.isRequired }
    }

    /// Gets all optional output ports
    public var optionalPorts: [OutputPort] {
        return filter { !$0.isRequired }
    }

    /// Finds a port by name
    /// - Parameter name: The port name to search for
    /// - Returns: The port if found, nil otherwise
    public func port(named name: String) -> OutputPort? {
        return first { $0.name == name }
    }

    /// Gets all ports that can connect to the specified signal type
    /// - Parameter signalType: The signal type to check compatibility with
    /// - Returns: Array of compatible output ports
    public func compatiblePorts(for signalType: SignalType) -> [OutputPort] {
        return filter { $0.canConnectTo(signalType) }
    }
}

// MARK: - Common Port Factory

extension InputPort {
    /// Creates a standard audio input port
    public static func audioInput(
        name: String = "input",
        displayName: String = "Input",
        isRequired: Bool = true
    ) -> InputPort {
        return InputPort(
            name: name,
            displayName: displayName,
            signalType: .audio,
            isRequired: isRequired
        )
    }

    /// Creates a frequency modulation input port
    public static func frequencyInput(
        name: String = "frequency",
        displayName: String = "Frequency",
        defaultValue: Double? = nil
    ) -> InputPort {
        return InputPort(
            name: name,
            displayName: displayName,
            signalType: .frequency,
            isRequired: false,
            defaultValue: defaultValue
        )
    }

    /// Creates an amplitude modulation input port
    public static func amplitudeInput(
        name: String = "amplitude",
        displayName: String = "Amplitude",
        defaultValue: Double? = nil
    ) -> InputPort {
        return InputPort(
            name: name,
            displayName: displayName,
            signalType: .amplitude,
            isRequired: false,
            defaultValue: defaultValue
        )
    }

    /// Creates a control voltage input port
    public static func controlInput(
        name: String,
        displayName: String,
        defaultValue: Double? = nil
    ) -> InputPort {
        return InputPort(
            name: name,
            displayName: displayName,
            signalType: .control,
            isRequired: false,
            defaultValue: defaultValue
        )
    }

    /// Creates a trigger input port
    public static func triggerInput(
        name: String = "trigger",
        displayName: String = "Trigger"
    ) -> InputPort {
        return InputPort(
            name: name,
            displayName: displayName,
            signalType: .trigger,
            isRequired: false,
            defaultValue: 0.0
        )
    }
}

extension OutputPort {
    /// Creates a standard audio output port
    public static func audioOutput(
        name: String = "output",
        displayName: String = "Output"
    ) -> OutputPort {
        return OutputPort(
            name: name,
            displayName: displayName,
            signalType: .audio
        )
    }

    /// Creates a control voltage output port
    public static func controlOutput(
        name: String,
        displayName: String
    ) -> OutputPort {
        return OutputPort(
            name: name,
            displayName: displayName,
            signalType: .control
        )
    }

    /// Creates a frequency output port
    public static func frequencyOutput(
        name: String = "frequency",
        displayName: String = "Frequency"
    ) -> OutputPort {
        return OutputPort(
            name: name,
            displayName: displayName,
            signalType: .frequency
        )
    }

    /// Creates a trigger output port
    public static func triggerOutput(
        name: String = "trigger",
        displayName: String = "Trigger"
    ) -> OutputPort {
        return OutputPort(
            name: name,
            displayName: displayName,
            signalType: .trigger
        )
    }
}
