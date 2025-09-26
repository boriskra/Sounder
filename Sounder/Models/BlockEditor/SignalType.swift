import Foundation

/// Defines the types of signals that can flow between blocks
/// Signal types ensure compatibility and proper routing in the block graph
public enum SignalType: String, CaseIterable, Codable, Equatable, Hashable {
    case audio           // Primary audio signal
    case control       // Control voltage/parameter modulation
    case trigger       // Gate/trigger signals
    case frequency   // Frequency control input
    case amplitude   // Amplitude control input

    /// Human-readable display name for the signal type
    public var displayName: String {
        switch self {
        case .audio: return "Audio"
        case .control: return "Control"
        case .trigger: return "Trigger"
        case .frequency: return "Frequency"
        case .amplitude: return "Amplitude"
        }
    }

    /// Detailed description of what this signal type represents
    public var description: String {
        switch self {
        case .audio:
            return "Full-bandwidth audio signals for listening or further processing"
        case .control:
            return "Control voltage signals for modulating parameters in real-time"
        case .trigger:
            return "Gate and trigger signals for timing and sequencing"
        case .frequency:
            return "Frequency control signals for oscillator and filter frequency modulation"
        case .amplitude:
            return "Amplitude control signals for volume and gain modulation"
        }
    }

    /// The expected value range for this signal type
    public var valueRange: ClosedRange<Double> {
        switch self {
        case .audio:
            return -1.0...1.0  // Normalized audio range
        case .control:
            return -1.0...1.0  // Bipolar control voltage
        case .trigger:
            return 0.0...1.0   // Unipolar gate/trigger
        case .frequency:
            return 20.0...20000.0  // Audio frequency range in Hz
        case .amplitude:
            return 0.0...1.0   // Unipolar amplitude (0-100%)
        }
    }

    /// The default unit for displaying values of this signal type
    public var unit: String {
        switch self {
        case .audio: return ""
        case .control: return "V"
        case .trigger: return ""
        case .frequency: return "Hz"
        case .amplitude: return "%"
        }
    }

    /// Color used for visualizing connections of this signal type
    public var visualColor: String {
        switch self {
        case .audio: return "#007AFF"      // Blue for audio
        case .control: return "#FF9500"    // Orange for control
        case .trigger: return "#FF3B30"    // Red for triggers
        case .frequency: return "#30D158"  // Green for frequency
        case .amplitude: return "#AF52DE"  // Purple for amplitude
        }
    }

    /// Checks if this signal type is compatible with another signal type
    /// - Parameter other: The other signal type to check compatibility with
    /// - Returns: True if the signal types can be connected
    public func isCompatible(with other: SignalType) -> Bool {
        return isDirectMatch(with: other) || isControlCompatible(with: other) || isSpecialCase(with: other)
    }

    /// Checks for direct signal type matches
    private func isDirectMatch(with other: SignalType) -> Bool {
        return self == other
    }

    /// Checks for control and modulation compatibility
    private func isControlCompatible(with other: SignalType) -> Bool {
        switch (self, other) {
        case (.control, .frequency), (.control, .amplitude):
            return true  // Control can modulate frequency/amplitude
        case (.frequency, .control), (.amplitude, .control):
            return true  // Frequency/amplitude can be used as control
        default:
            return false
        }
    }

    /// Checks for special conversion cases
    private func isSpecialCase(with other: SignalType) -> Bool {
        return self == .audio && other == .control  // Audio can be converted to control for analysis
    }

    /// Gets all signal types that this signal type can connect to
    /// - Returns: Array of compatible signal types
    public var compatibleTypes: [SignalType] {
        return SignalType.allCases.filter { isCompatible(with: $0) }
    }

    /// Checks if this signal type represents an audio signal that can be heard
    public var isAudible: Bool {
        return self == .audio
    }

    /// Checks if this signal type represents a control/modulation signal
    public var isControl: Bool {
        return [.control, .frequency, .amplitude].contains(self)
    }

    /// Checks if this signal type represents a timing/synchronization signal
    public var isTiming: Bool {
        return self == .trigger
    }

    /// Gets the priority for automatic connection suggestions
    /// Higher values indicate higher priority for automatic routing
    public var connectionPriority: Int {
        switch self {
        case .audio: return 100      // Highest priority - main signal path
        case .frequency: return 80   // High priority - important modulation
        case .amplitude: return 70   // High priority - volume control
        case .control: return 60     // Medium priority - general modulation
        case .trigger: return 40     // Lower priority - timing signals
        }
    }

    /// Converts a value from this signal type's range to a normalized 0-1 range
    /// - Parameter value: Value in the signal type's native range
    /// - Returns: Normalized value between 0 and 1
    public func normalize(_ value: Double) -> Double {
        let range: ClosedRange<Double> = valueRange
        let clampedValue: Double = min(max(value, range.lowerBound), range.upperBound)
        return (clampedValue - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    /// Converts a normalized 0-1 value to this signal type's native range
    /// - Parameter normalizedValue: Value between 0 and 1
    /// - Returns: Value in the signal type's native range
    public func denormalize(_ normalizedValue: Double) -> Double {
        let clampedNormalized: Double = min(max(normalizedValue, 0.0), 1.0)
        let range: ClosedRange<Double> = valueRange
        return range.lowerBound + clampedNormalized * (range.upperBound - range.lowerBound)
    }

    /// Formats a value for display with appropriate precision and units
    /// - Parameter value: Value to format
    /// - Returns: Formatted string with units
    public func formatValue(_ value: Double) -> String {
        let clampedValue: Double = min(max(value, valueRange.lowerBound), valueRange.upperBound)

        switch self {
        case .audio:
            return String(format: "%.3f", clampedValue)
        case .control:
            return String(format: "%.2f %@", clampedValue, unit)
        case .trigger:
            return clampedValue > 0.5 ? "HIGH" : "LOW"
        case .frequency:
            if clampedValue >= 1000 {
                return String(format: "%.1f kHz", clampedValue / 1000)
            } else {
                return String(format: "%.0f Hz", clampedValue)
            }
        case .amplitude:
            return String(format: "%.0f%%", clampedValue * 100)
        }
    }

    /// Gets the typical refresh rate for this signal type in Hz
    /// Used for optimizing real-time updates and visualizations
    public var refreshRate: Double {
        switch self {
        case .audio: return 48000.0     // Audio sample rate
        case .control: return 1000.0    // Control rate updates
        case .trigger: return 1000.0    // Trigger event rate
        case .frequency: return 100.0   // Frequency modulation rate
        case .amplitude: return 100.0   // Amplitude modulation rate
        }
    }

    /// Checks if values of this signal type should be smoothed during parameter changes
    /// to avoid audio artifacts
    public var requiresSmoothing: Bool {
        switch self {
        case .audio: return true        // Always smooth audio to avoid clicks
        case .frequency: return true    // Smooth frequency changes
        case .amplitude: return true    // Smooth amplitude changes
        case .control: return true      // Smooth control changes
        case .trigger: return false     // Triggers should be immediate
        }
    }

    /// Gets the recommended smoothing time constant in seconds
    /// for parameter changes of this signal type
    public var smoothingTimeConstant: Double {
        switch self {
        case .audio: return 0.01        // 10ms for audio smoothing
        case .frequency: return 0.02    // 20ms for frequency changes
        case .amplitude: return 0.01    // 10ms for amplitude changes
        case .control: return 0.05      // 50ms for control changes
        case .trigger: return 0.0       // No smoothing for triggers
        }
    }

    /// Groups signal types by their primary function
    public static let audioSignals: [SignalType] = [.audio]
    public static let controlSignals: [SignalType] = [.control, .frequency, .amplitude]
    public static let timingSignals: [SignalType] = [.trigger]

    /// Gets all signal types suitable for modulation inputs
    public static let modulationSignals: [SignalType] = [.control, .frequency, .amplitude, .audio]

    /// Gets all signal types that can be used as analysis inputs
    public static let analysisInputs: [SignalType] = [.audio, .control]

    /// Gets all signal types that can be generated by oscillators
    public static let generatorOutputs: [SignalType] = [.audio, .control]
}

// MARK: - Signal Type Conversion

extension SignalType {
    /// Converts a value from one signal type to another with appropriate scaling
    /// - Parameters:
    ///   - value: Value in the source signal type's range
    ///   - to: Target signal type
    /// - Returns: Converted value in the target signal type's range
    public func convertValue(_ value: Double, to targetType: SignalType) -> Double {
        guard isCompatible(with: targetType) else {
            return targetType.valueRange.lowerBound
        }

        // Normalize the value from source type
        let normalizedValue: Double = normalize(value)

        // Denormalize to target type
        return targetType.denormalize(normalizedValue)
    }

    /// Gets the conversion factor between this signal type and another
    /// - Parameter other: Target signal type
    /// - Returns: Multiplication factor for direct conversion, or nil if incompatible
    public func conversionFactor(to other: SignalType) -> Double? {
        guard isCompatible(with: other) else { return nil }

        let sourceRange: Double = valueRange.upperBound - valueRange.lowerBound
        let targetRange: Double = other.valueRange.upperBound - other.valueRange.lowerBound

        return targetRange / sourceRange
    }
}

// MARK: - Connection Validation

extension SignalType {
    /// Validates that a connection between two signal types is allowed
    /// - Parameters:
    ///   - source: Source signal type
    ///   - destination: Destination signal type
    /// - Returns: Validation result with optional warnings
    public static func validateConnection(from source: SignalType, to destination: SignalType) -> ConnectionValidation {
        if source.isCompatible(with: destination) {
            // Check for potential issues
            if source == .audio && destination == .control {
                return .warning("Connecting audio to control may cause unexpected modulation")
            } else if source.connectionPriority < destination.connectionPriority {
                return .warning("Consider using a higher-priority signal for this connection")
            } else {
                return .valid
            }
        } else {
            return .invalid("Signal type \(source.displayName) cannot connect to \(destination.displayName)")
        }
    }
}

// MARK: - Connection Validation Result

/// Result of connection validation between signal types
public enum ConnectionValidation {
    /// Connection is valid and recommended
    case valid
    /// Connection is valid but has potential issues
    case warning(String)
    /// Connection is not allowed
    case invalid(String)

    /// Whether the connection is allowed
    public var isValid: Bool {
        switch self {
        case .valid, .warning: return true
        case .invalid: return false
        }
    }

    /// Optional message providing details about the validation result
    public var message: String? {
        switch self {
        case .valid: return nil
        case .warning(let message), .invalid(let message): return message
        }
    }
}
