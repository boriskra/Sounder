import SwiftUI

/// Category grouping for UI organization
public enum BlockCategory: String, CaseIterable, Codable {
    case generators
    case modulation
    case processing
    case analysis
    case output

    public var displayName: String {
        switch self {
        case .generators: return "Generators"
        case .modulation: return "Modulation"
        case .processing: return "Processing"
        case .analysis: return "Analysis"
        case .output: return "Output"
        }
    }

    public var description: String {
        switch self {
        case .generators: return "Signal generation blocks"
        case .modulation: return "Signal modulation blocks"
        case .processing: return "Signal processing blocks"
        case .analysis: return "Signal analysis blocks"
        case .output: return "Audio output blocks"
        }
    }

    /// Gets all block types in this category
    public var blockTypes: [BlockType] {
        return BlockType.allCases.filter { $0.category == self }
    }

    /// Color associated with this category for UI
    public var color: Color {
        switch self {
        case .generators: return .blue
        case .modulation: return .purple
        case .processing: return .green
        case .analysis: return .orange
        case .output: return .red
        }
    }
}
