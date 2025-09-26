import Foundation
import SwiftUI

/// Represents a functional audio processing unit in the visual interface
/// Each SignalBlock corresponds to a specific audio operation (generation, processing, analysis)
public struct SignalBlock: Identifiable, Codable, Equatable {
    public let id: UUID
    public let type: BlockType
    public var title: String
    public var position: CGPoint
    public var parameters: [String: BlockParameter]
    public var inputPorts: [InputPort]
    public var outputPorts: [OutputPort]
    public var isActive: Bool

    /// Creates a new SignalBlock with the specified properties
    /// - Parameters:
    ///   - id: Unique identifier for the block
    ///   - type: The type of audio processing this block performs
    ///   - title: Display name for the block
    ///   - position: Canvas coordinates (x, y)
    ///   - parameters: Configurable properties specific to the block type
    ///   - inputPorts: Available input connections
    ///   - outputPorts: Available output connections
    ///   - isActive: Whether block is currently processing audio
    public init(
        id: UUID = UUID(),
        type: BlockType,
        title: String,
        position: CGPoint,
        parameters: [String: BlockParameter] = [:],
        inputPorts: [InputPort] = [],
        outputPorts: [OutputPort] = [],
        isActive: Bool = false
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.position = position
        self.parameters = parameters
        self.inputPorts = inputPorts
        self.outputPorts = outputPorts
        self.isActive = isActive

        // Validate the block after initialization
        self.validateBlock()
    }

    /// Computed property that returns input port names as string array for UI compatibility
    public var inputPortNames: [String] {
        return inputPorts.map { $0.name }
    }

    /// Computed property that returns output port names as string array for UI compatibility
    public var outputPortNames: [String] {
        return outputPorts.map { $0.name }
    }

    /// Validates the block configuration according to business rules
    /// Throws fatal errors for invalid configurations that should be caught during development
    private func validateBlock() {
        // Validation Rule: Position coordinates must be non-negative
        precondition(position.x >= 0 && position.y >= 0,
                    "Block position coordinates must be non-negative. Got: \(position)")

        // Validation Rule: Title must not be empty
        precondition(!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Block title must not be empty")

        // Validation Rule: Parameters must contain all required parameters for the block type
        let requiredParameters: [String] = type.requiredParameters
        for requiredParam in requiredParameters {
            precondition(parameters.keys.contains(requiredParam),
                        "Block of type \(type) missing required parameter: \(requiredParam)")
        }

        // Validation Rule: At least one output port required for generator blocks
        if type.isGenerator {
            precondition(!outputPorts.isEmpty,
                        "Generator blocks must have at least one output port")
        }

        // Validation Rule: Parameter values must be within valid ranges
        for (paramName, parameter) in parameters {
            precondition(parameter.value >= parameter.minimumValue,
                        "Parameter \(paramName) value \(parameter.value) below minimum \(parameter.minimumValue)")
            precondition(parameter.value <= parameter.maximumValue,
                        "Parameter \(paramName) value \(parameter.value) above maximum \(parameter.maximumValue)")
        }

        // Validation Rule: Port names must be unique within input and output arrays
        let inputPortNames: [String] = inputPorts.map { $0.name }
        precondition(inputPortNames.count == Set(inputPortNames).count,
                    "Input port names must be unique")

        let outputPortNames: [String] = outputPorts.map { $0.name }
        precondition(outputPortNames.count == Set(outputPortNames).count,
                    "Output port names must be unique")
    }

    /// Updates a parameter value with validation
    /// - Parameters:
    ///   - parameterName: Name of the parameter to update
    ///   - value: New value for the parameter
    /// - Returns: Updated SignalBlock instance
    /// - Throws: ValidationError if parameter is invalid or value is out of range
    public func updatingParameter(_ parameterName: String, to value: Double) throws -> SignalBlock {
        guard var parameter = parameters[parameterName] else {
            throw ValidationError.parameterNotFound(parameterName)
        }

        guard value >= parameter.minimumValue && value <= parameter.maximumValue else {
            throw ValidationError.parameterValueOutOfRange(
                parameter: parameterName,
                value: value,
                range: parameter.minimumValue...parameter.maximumValue
            )
        }

        parameter.value = value
        var updatedParameters: [String: BlockParameter] = parameters
        updatedParameters[parameterName] = parameter

        return SignalBlock(
            id: id,
            type: type,
            title: title,
            position: position,
            parameters: updatedParameters,
            inputPorts: inputPorts,
            outputPorts: outputPorts,
            isActive: isActive
        )
    }

    /// Updates the block's position
    /// - Parameter newPosition: New canvas coordinates
    /// - Returns: Updated SignalBlock instance
    /// - Throws: ValidationError if position is invalid
    public func movingTo(_ newPosition: CGPoint) throws -> SignalBlock {
        guard newPosition.x >= 0 && newPosition.y >= 0 else {
            throw ValidationError.invalidPosition(newPosition)
        }

        return SignalBlock(
            id: id,
            type: type,
            title: title,
            position: newPosition,
            parameters: parameters,
            inputPorts: inputPorts,
            outputPorts: outputPorts,
            isActive: isActive
        )
    }

    /// Updates the block's active state
    /// - Parameter active: Whether the block should be active
    /// - Returns: Updated SignalBlock instance
    public func settingActive(_ active: Bool) -> SignalBlock {
        return SignalBlock(
            id: id,
            type: type,
            title: title,
            position: position,
            parameters: parameters,
            inputPorts: inputPorts,
            outputPorts: outputPorts,
            isActive: active
        )
    }

    /// Gets the visual size of the block for rendering
    /// Size depends on the number of ports and parameters
    public var visualSize: CGSize {
        let baseWidth: CGFloat = 120
        let baseHeight: CGFloat = 80

        // Add width for parameters
        let parameterWidth: CGFloat = max(0, CGFloat(parameters.count - 2) * 20)

        // Add height for ports
        let maxPorts: Int = max(inputPorts.count, outputPorts.count)
        let portHeight: CGFloat = max(0, CGFloat(maxPorts - 2) * 25)

        return CGSize(
            width: baseWidth + parameterWidth,
            height: baseHeight + portHeight
        )
    }

    /// Gets the input port by name
    /// - Parameter name: Name of the input port
    /// - Returns: The input port if found
    public func inputPort(named name: String) -> InputPort? {
        return inputPorts.first { $0.name == name }
    }

    /// Gets the output port by name
    /// - Parameter name: Name of the output port
    /// - Returns: The output port if found
    public func outputPort(named name: String) -> OutputPort? {
        return outputPorts.first { $0.name == name }
    }

    /// Checks if the block has all required inputs connected
    /// - Parameter connections: Array of connections to check against
    /// - Returns: True if all required inputs are connected
    public func hasRequiredInputsConnected(connections: [Connection]) -> Bool {
        let requiredInputs: [InputPort] = inputPorts.filter { $0.isRequired }

        for requiredInput in requiredInputs {
            let isConnected: Bool = connections.contains { connection in
                connection.destinationBlockId == id && connection.destinationPort == requiredInput.name
            }

            if !isConnected && requiredInput.defaultValue == nil {
                return false
            }
        }

        return true
    }
}

// MARK: - Validation Errors

public enum ValidationError: Error, LocalizedError {
    case parameterNotFound(String)
    case parameterValueOutOfRange(parameter: String, value: Double, range: ClosedRange<Double>)
    case invalidPosition(CGPoint)
    case missingRequiredParameter(String)
    case invalidPortConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case .parameterNotFound(let parameter):
            return "Parameter '\(parameter)' not found"
        case .parameterValueOutOfRange(let parameter, let value, let range):
            return "Parameter '\(parameter)' value \(value) is outside valid range \(range.lowerBound)...\(range.upperBound)"
        case .invalidPosition(let position):
            return "Invalid position \(position). Coordinates must be non-negative"
        case .missingRequiredParameter(let parameter):
            return "Missing required parameter: \(parameter)"
        case .invalidPortConfiguration(let message):
            return "Invalid port configuration: \(message)"
        }
    }
}

// MARK: - Codable Support

extension SignalBlock {
    public enum CodingKeys: String, CodingKey {
        case id, type, title, position, parameters, inputPorts, outputPorts, isActive
    }

    /// Decodes a SignalBlock from the given decoder
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(BlockType.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        position = try container.decode(CGPoint.self, forKey: .position)
        parameters = try container.decode([String: BlockParameter].self, forKey: .parameters)
        inputPorts = try container.decode([InputPort].self, forKey: .inputPorts)
        outputPorts = try container.decode([OutputPort].self, forKey: .outputPorts)
        isActive = try container.decode(Bool.self, forKey: .isActive)

        // Validate after decoding
        self.validateBlock()
    }
}

// MARK: - Equatable Support

extension SignalBlock {
    /// Compares two signal blocks for equality based on all properties
    public static func == (lhs: SignalBlock, rhs: SignalBlock) -> Bool {
        return lhs.id == rhs.id &&
               lhs.type == rhs.type &&
               lhs.title == rhs.title &&
               lhs.position == rhs.position &&
               lhs.parameters == rhs.parameters &&
               lhs.inputPorts == rhs.inputPorts &&
               lhs.outputPorts == rhs.outputPorts &&
               lhs.isActive == rhs.isActive
    }
}
