import Foundation

/// Represents an audio output device available in the system
/// Used for routing generated audio to specific hardware devices
public struct OutputDevice: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let isDefault: Bool
    public let isAvailable: Bool

    /// Creates a new OutputDevice
    /// - Parameters:
    ///   - id: Unique system identifier for the device
    ///   - name: Human-readable name of the device
    ///   - isDefault: Whether this is the system's default output device
    ///   - isAvailable: Whether the device is currently available for use
    public init(id: String, name: String, isDefault: Bool, isAvailable: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.isAvailable = isAvailable
    }

    /// Display text for the device in UI
    public var displayName: String {
        var text: String = name
        if isDefault {
            text += " (Default)"
        }
        if !isAvailable {
            text += " (Unavailable)"
        }
        return text
    }

    /// Checks if this device appears to be a Bluetooth device
    public var isBluetoothDevice: Bool {
        return name.lowercased().contains("bluetooth") ||
               name.lowercased().contains("airpods") ||
               name.lowercased().contains("wireless")
    }

    /// Checks if this device is suitable for audio output
    public var isSuitableForOutput: Bool {
        return isAvailable && !name.lowercased().contains("input")
    }
}
