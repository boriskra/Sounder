import Foundation

/// Represents a configurable property of a signal block
/// Each parameter has a name, current value, valid range, and display properties
public struct BlockParameter: Codable, Equatable, Hashable {
    public let name: String
    public let displayName: String
    public var value: Double
    public let minimumValue: Double
    public let maximumValue: Double
    public let unit: String
    public let stepSize: Double
    public let isLogarithmic: Bool

    /// Creates a new BlockParameter with validation
    /// - Parameters:
    ///   - name: Parameter identifier (e.g., "frequency", "amplitude")
    ///   - displayName: Human-readable label for UI
    ///   - value: Current numeric value
    ///   - minimumValue: Minimum allowed value
    ///   - maximumValue: Maximum allowed value
    ///   - unit: Unit of measurement (Hz, dB, %, etc.)
    ///   - stepSize: Increment/decrement step for UI controls
    ///   - isLogarithmic: Whether to use log scale for display
    public init(
        name: String,
        displayName: String,
        value: Double,
        minimumValue: Double,
        maximumValue: Double,
        unit: String,
        stepSize: Double,
        isLogarithmic: Bool = false
    ) {
        // Validate inputs
        precondition(!name.isEmpty, "Parameter name cannot be empty")
        precondition(!displayName.isEmpty, "Parameter display name cannot be empty")
        precondition(minimumValue <= maximumValue, "Minimum value \(minimumValue) must be <= maximum value \(maximumValue)")
        precondition(stepSize > 0, "Step size must be positive, got: \(stepSize)")
        precondition(value >= minimumValue && value <= maximumValue,
                    "Value \(value) must be between \(minimumValue) and \(maximumValue)")

        self.name = name
        self.displayName = displayName
        self.value = value
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.unit = unit
        self.stepSize = stepSize
        self.isLogarithmic = isLogarithmic
    }

    /// Validates and sets a new value for the parameter
    /// - Parameter newValue: The new value to set
    /// - Returns: Updated BlockParameter with the new value
    /// - Throws: ParameterError if value is out of range
    public func settingValue(_ newValue: Double) throws -> BlockParameter {
        guard newValue >= minimumValue && newValue <= maximumValue else {
            throw ParameterError.valueOutOfRange(
                parameter: name,
                value: newValue,
                range: minimumValue...maximumValue
            )
        }

        return BlockParameter(
            name: name,
            displayName: displayName,
            value: newValue,
            minimumValue: minimumValue,
            maximumValue: maximumValue,
            unit: unit,
            stepSize: stepSize,
            isLogarithmic: isLogarithmic
        )
    }

    /// Increments the parameter value by the step size
    /// - Returns: Updated BlockParameter with incremented value
    /// - Throws: ParameterError if increment would exceed maximum
    public func incrementing() throws -> BlockParameter {
        let newValue: Double = value + stepSize
        return try settingValue(min(newValue, maximumValue))
    }

    /// Decrements the parameter value by the step size
    /// - Returns: Updated BlockParameter with decremented value
    /// - Throws: ParameterError if decrement would go below minimum
    public func decrementing() throws -> BlockParameter {
        let newValue: Double = value - stepSize
        return try settingValue(max(newValue, minimumValue))
    }

    /// Gets the parameter value as a percentage of the range (0.0 to 1.0)
    /// Useful for UI sliders and normalized representations
    public var normalizedValue: Double {
        guard maximumValue != minimumValue else { return 0.0 }

        if isLogarithmic {
            // For logarithmic scales, use log space normalization
            let logMin: Double = log10(max(minimumValue, 0.001)) // Avoid log(0)
            let logMax: Double = log10(maximumValue)
            let logValue: Double = log10(max(value, 0.001))
            return (logValue - logMin) / (logMax - logMin)
        } else {
            // Linear normalization
            return (value - minimumValue) / (maximumValue - minimumValue)
        }
    }

    /// Sets the parameter value from a normalized value (0.0 to 1.0)
    /// - Parameter normalizedValue: Value between 0.0 and 1.0
    /// - Returns: Updated BlockParameter with the denormalized value
    /// - Throws: ParameterError if normalized value is out of range
    public func settingNormalizedValue(_ normalizedValue: Double) throws -> BlockParameter {
        guard normalizedValue >= 0.0 && normalizedValue <= 1.0 else {
            throw ParameterError.normalizedValueOutOfRange(normalizedValue)
        }

        let denormalizedValue: Double

        if isLogarithmic {
            // Convert from log space
            let logMin: Double = log10(max(minimumValue, 0.001))
            let logMax: Double = log10(maximumValue)
            let logValue: Double = logMin + normalizedValue * (logMax - logMin)
            denormalizedValue = pow(10, logValue)
        } else {
            // Linear denormalization
            denormalizedValue = minimumValue + normalizedValue * (maximumValue - minimumValue)
        }

        return try settingValue(denormalizedValue)
    }

    /// Gets the formatted display string for the parameter value
    /// Includes appropriate precision and unit
    public var formattedValue: String {
        let precision: Int = determinePrecision()
        let formattedNumber: String = String(format: "%.\(precision)f", value)
        return "\(formattedNumber) \(unit)".trimmingCharacters(in: .whitespaces)
    }

    /// Gets the formatted display string for the parameter range
    public var formattedRange: String {
        let precision: Int = determinePrecision()
        let minFormatted: String = String(format: "%.\(precision)f", minimumValue)
        let maxFormatted: String = String(format: "%.\(precision)f", maximumValue)
        return "\(minFormatted) - \(maxFormatted) \(unit)".trimmingCharacters(in: .whitespaces)
    }

    /// Determines appropriate decimal precision based on the parameter range and step size
    private func determinePrecision() -> Int {
        let range: Double = maximumValue - minimumValue

        if stepSize >= 1.0 || range >= 1000 {
            return 0  // No decimal places for large values
        } else if stepSize >= 0.1 || range >= 100 {
            return 1  // One decimal place
        } else if stepSize >= 0.01 || range >= 10 {
            return 2  // Two decimal places
        } else {
            return 3  // Three decimal places for precise values
        }
    }

    /// Validates that the parameter is appropriate for the given unit type
    public func validateUnit() throws {
        switch unit.lowercased() {
        case "hz":
            // Frequency values should be positive
            guard minimumValue >= 0 else {
                throw ParameterError.invalidUnitRange(unit: unit, reason: "Frequency values cannot be negative")
            }
        case "db":
            // dB values typically range from negative to positive
            // No specific validation needed
            break
        case "%":
            // Percentage values should be 0-100
            guard minimumValue >= 0 && maximumValue <= 100 else {
                throw ParameterError.invalidUnitRange(unit: unit, reason: "Percentage values should be 0-100")
            }
        case "s", "ms":
            // Time values should be positive
            guard minimumValue >= 0 else {
                throw ParameterError.invalidUnitRange(unit: unit, reason: "Time values cannot be negative")
            }
        default:
            // Other units are accepted without specific validation
            break
        }
    }

    /// Checks if the parameter represents a frequency value
    public var isFrequency: Bool {
        return unit.lowercased() == "hz"
    }

    /// Checks if the parameter represents an amplitude/volume value
    public var isAmplitude: Bool {
        return unit.lowercased() == "db" || name.lowercased().contains("gain") || name.lowercased().contains("amplitude")
    }

    /// Checks if the parameter represents a time value
    public var isTime: Bool {
        return unit.lowercased() == "s" || unit.lowercased() == "ms"
    }

    /// Gets the parameter value clamped to the valid range
    /// Useful for ensuring values stay within bounds after calculations
    public var clampedValue: Double {
        return min(max(value, minimumValue), maximumValue)
    }
}

// MARK: - Parameter Errors

public enum ParameterError: Error, LocalizedError {
    case valueOutOfRange(parameter: String, value: Double, range: ClosedRange<Double>)
    case normalizedValueOutOfRange(Double)
    case invalidUnitRange(unit: String, reason: String)
    case invalidStepSize(Double)

    public var errorDescription: String? {
        switch self {
        case .valueOutOfRange(let parameter, let value, let range):
            return "Parameter '\(parameter)' value \(value) is outside valid range \(range.lowerBound)...\(range.upperBound)"
        case .normalizedValueOutOfRange(let value):
            return "Normalized value \(value) must be between 0.0 and 1.0"
        case .invalidUnitRange(let unit, let reason):
            return "Invalid range for unit '\(unit)': \(reason)"
        case .invalidStepSize(let stepSize):
            return "Invalid step size \(stepSize). Step size must be positive"
        }
    }
}

// MARK: - Common Parameter Factory

extension BlockParameter {
    /// Creates a frequency parameter with typical audio ranges
    /// - Parameters:
    ///   - name: Parameter name
    ///   - displayName: Display name
    ///   - value: Initial frequency in Hz
    ///   - minHz: Minimum frequency (default: 20 Hz)
    ///   - maxHz: Maximum frequency (default: 20,000 Hz)
    /// - Returns: Configured frequency parameter
    public static func frequency(
        name: String = "frequency",
        displayName: String = "Frequency",
        value: Double = 440.0,
        minHz: Double = 20.0,
        maxHz: Double = 20000.0
    ) -> BlockParameter {
        return BlockParameter(
            name: name,
            displayName: displayName,
            value: value,
            minimumValue: minHz,
            maximumValue: maxHz,
            unit: "Hz",
            stepSize: value < 1000 ? 1.0 : 10.0,
            isLogarithmic: true
        )
    }

    /// Creates an amplitude parameter with dB scale
    /// - Parameters:
    ///   - name: Parameter name
    ///   - displayName: Display name
    ///   - value: Initial amplitude in dB
    ///   - minDb: Minimum amplitude (default: -60 dB)
    ///   - maxDb: Maximum amplitude (default: 0 dB)
    /// - Returns: Configured amplitude parameter
    public static func amplitude(
        name: String = "amplitude",
        displayName: String = "Amplitude",
        value: Double = -6.0,
        minDb: Double = -60.0,
        maxDb: Double = 0.0
    ) -> BlockParameter {
        return BlockParameter(
            name: name,
            displayName: displayName,
            value: value,
            minimumValue: minDb,
            maximumValue: maxDb,
            unit: "dB",
            stepSize: 0.1,
            isLogarithmic: false
        )
    }

    /// Creates a percentage parameter (0-100%)
    /// - Parameters:
    ///   - name: Parameter name
    ///   - displayName: Display name
    ///   - value: Initial percentage value
    /// - Returns: Configured percentage parameter
    public static func percentage(
        name: String,
        displayName: String,
        value: Double = 50.0
    ) -> BlockParameter {
        return BlockParameter(
            name: name,
            displayName: displayName,
            value: value,
            minimumValue: 0.0,
            maximumValue: 100.0,
            unit: "%",
            stepSize: 1.0,
            isLogarithmic: false
        )
    }

    /// Creates a time parameter with seconds or milliseconds
    /// - Parameters:
    ///   - name: Parameter name
    ///   - displayName: Display name
    ///   - value: Initial time value
    ///   - minTime: Minimum time
    ///   - maxTime: Maximum time
    ///   - useMilliseconds: Whether to use milliseconds instead of seconds
    /// - Returns: Configured time parameter
    public static func time(
        name: String,
        displayName: String,
        value: Double,
        minTime: Double,
        maxTime: Double,
        useMilliseconds: Bool = false
    ) -> BlockParameter {
        return BlockParameter(
            name: name,
            displayName: displayName,
            value: value,
            minimumValue: minTime,
            maximumValue: maxTime,
            unit: useMilliseconds ? "ms" : "s",
            stepSize: useMilliseconds ? 1.0 : 0.01,
            isLogarithmic: false
        )
    }
}
