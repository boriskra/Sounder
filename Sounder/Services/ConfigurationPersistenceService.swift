import Foundation
import SwiftUI

/// Service for persisting block configurations to JSON files with versioning and validation
class ConfigurationPersistenceService: ObservableObject {

    // MARK: - Constants

    private let currentVersion: String = "1.0"
    private let fileExtension: String = "sounder"
    private let backupExtension: String = "backup"

    // MARK: - File Management

    private let documentsDirectory: URL
    private let configurationsDirectory: URL
    private let backupsDirectory: URL

    // MARK: - JSON Coding

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - Initialization

    init() {
        // Setup directories
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Documents directory not found.")
        }
        documentsDirectory = documentsURL
        configurationsDirectory = documentsURL.appendingPathComponent("Sounder Configurations")
        backupsDirectory = configurationsDirectory.appendingPathComponent("Backups")

        // Setup JSON coding
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        setupDirectories()
    }

    private func setupDirectories() {
        do {
            try FileManager.default.createDirectory(
                at: configurationsDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )

            try FileManager.default.createDirectory(
                at: backupsDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            print("Failed to create configuration directories: \(error)")
        }
    }

    // MARK: - Save Operations

    /// Saves a block configuration to the specified URL
    /// - Parameters:
    ///   - configuration: The configuration to save
    ///   - url: The destination URL
    /// - Throws: ConfigurationPersistenceError if save fails
    func saveConfiguration(_ configuration: BlockConfiguration, to url: URL) async throws {
        // Validate configuration before saving
        try validateConfiguration(configuration)

        // Create persistable configuration
        let persistableConfig: PersistableConfiguration = PersistableConfiguration(from: configuration, version: currentVersion)

        // Create backup if file exists
        if FileManager.default.fileExists(atPath: url.path) {
            try createBackup(of: url)
        }

        do {
            let data: Data = try encoder.encode(persistableConfig)
            try data.write(to: url, options: .atomic)

            print("Configuration saved to: \(url.path)")
            print("File size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")

        } catch {
            throw ConfigurationPersistenceError.saveFailed(url.path, error.localizedDescription)
        }
    }

    /// Saves configuration with auto-generated filename
    /// - Parameter configuration: The configuration to save
    /// - Returns: The URL where the configuration was saved
    /// - Throws: ConfigurationPersistenceError if save fails
    func saveConfigurationWithAutoName(_ configuration: BlockConfiguration) async throws -> URL {
        let filename: String = generateAutoFilename(for: configuration)
        let url: URL = configurationsDirectory.appendingPathComponent(filename)

        try await saveConfiguration(configuration, to: url)
        return url
    }

    private func generateAutoFilename(for configuration: BlockConfiguration) -> String {
        let dateFormatter: DateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp: String = dateFormatter.string(from: Date())

        let blockCount: Int = configuration.blocks.count
        let baseName: String = "Configuration_\(blockCount)blocks_\(timestamp)"

        return "\(baseName).\(fileExtension)"
    }

    // MARK: - Load Operations

    /// Loads a block configuration from the specified URL
    /// - Parameter url: The source URL
    /// - Returns: The loaded configuration
    /// - Throws: ConfigurationPersistenceError if load fails
    func loadConfiguration(from url: URL) async throws -> BlockConfiguration {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigurationPersistenceError.fileNotFound(url.path)
        }

        do {
            let data: Data = try Data(contentsOf: url)
            let persistableConfig: PersistableConfiguration = try decoder.decode(PersistableConfiguration.self, from: data)

            // Validate version compatibility
            try validateVersion(persistableConfig.version)

            // Convert to runtime configuration
            let configuration: BlockConfiguration = try persistableConfig.toConfiguration()

            // Validate loaded configuration
            try validateConfiguration(configuration)

            print("Configuration loaded from: \(url.path)")
            print("Version: \(persistableConfig.version)")
            print("Blocks: \(configuration.blocks.count), Connections: \(configuration.connections.count)")

            return configuration

        } catch let error as ConfigurationPersistenceError {
            throw error
        } catch {
            throw ConfigurationPersistenceError.loadFailed(url.path, error.localizedDescription)
        }
    }

    // MARK: - Export Operations

    /// Exports configuration to various formats
    /// - Parameters:
    ///   - configuration: The configuration to export
    ///   - format: The export format
    ///   - url: The destination URL
    /// - Throws: ConfigurationPersistenceError if export fails
    func exportConfiguration(
        _ configuration: BlockConfiguration,
        format: ExportFormat,
        to url: URL
    ) async throws {
        switch format {
        case .json:
            try await exportAsJSON(configuration, to: url)
        case .xml:
            try await exportAsXML(configuration, to: url)
        case .preset:
            try await exportAsPreset(configuration, to: url)
        case .csv:
            try await exportAsCSV(configuration, to: url)
        }
    }

    private func exportAsJSON(_ configuration: BlockConfiguration, to url: URL) async throws {
        // Export with additional metadata
        let exportData: ExportData = ExportData(
            format: "json",
            exportedAt: Date(),
            exportedBy: "Sounder",
            configuration: PersistableConfiguration(from: configuration, version: currentVersion)
        )

        let data: Data = try encoder.encode(exportData)
        try data.write(to: url)
    }

    private func exportAsXML(_ configuration: BlockConfiguration, to url: URL) async throws {
        let xmlExporter: XMLConfigurationExporter = XMLConfigurationExporter()
        let xmlContent: String = xmlExporter.export(configuration)
        try xmlContent.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportAsPreset(_ configuration: BlockConfiguration, to url: URL) async throws {
        let preset: ConfigurationPreset = ConfigurationPreset(
            name: url.deletingPathExtension().lastPathComponent,
            description: "Exported from Sounder",
            category: "User Presets",
            tags: extractTags(from: configuration),
            configuration: configuration,
            createdAt: Date(),
            compatibility: PresetCompatibility(
                minVersion: "1.0",
                maxVersion: currentVersion,
                requiredFeatures: extractRequiredFeatures(from: configuration)
            )
        )

        let data: Data = try encoder.encode(preset)
        try data.write(to: url)
    }

    private func exportAsCSV(_ configuration: BlockConfiguration, to url: URL) async throws {
        let csvExporter: CSVConfigurationExporter = CSVConfigurationExporter()
        let csvContent: String = csvExporter.export(configuration)
        try csvContent.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Import Operations

    /// Imports configuration from various formats
    /// - Parameters:
    ///   - url: The source URL
    ///   - format: The expected format (auto-detected if nil)
    /// - Returns: The imported configuration
    /// - Throws: ConfigurationPersistenceError if import fails
    func importConfiguration(from url: URL, format: ImportFormat? = nil) async throws -> BlockConfiguration {
        let detectedFormat: ImportFormat = format ?? detectFormat(from: url)

        switch detectedFormat {
        case .json:
            return try await importFromJSON(url)
        case .xml:
            return try await importFromXML(url)
        case .preset:
            return try await importFromPreset(url)
        case .legacy:
            return try await importFromLegacy(url)
        }
    }

    private func importFromJSON(_ url: URL) async throws -> BlockConfiguration {
        let data: Data = try Data(contentsOf: url)

        // Try different JSON structures
        if let exportData = try? decoder.decode(ExportData.self, from: data) {
            return try exportData.configuration.toConfiguration()
        } else if let persistableConfig = try? decoder.decode(PersistableConfiguration.self, from: data) {
            return try persistableConfig.toConfiguration()
        } else {
            throw ConfigurationPersistenceError.invalidFormat("Unrecognized JSON structure")
        }
    }

    private func importFromXML(_ url: URL) async throws -> BlockConfiguration {
        let xmlImporter: XMLConfigurationImporter = XMLConfigurationImporter()
        return try xmlImporter.import(from: url)
    }

    private func importFromPreset(_ url: URL) async throws -> BlockConfiguration {
        let data: Data = try Data(contentsOf: url)
        let preset: ConfigurationPreset = try decoder.decode(ConfigurationPreset.self, from: data)

        // Check compatibility
        try validatePresetCompatibility(preset.compatibility)

        return preset.configuration
    }

    private func importFromLegacy(_ url: URL) async throws -> BlockConfiguration {
        // Handle legacy file formats if needed
        throw ConfigurationPersistenceError.unsupportedFormat("Legacy format not yet supported")
    }

    // MARK: - Backup Management

    private func createBackup(of url: URL) throws {
        let filename: String = url.lastPathComponent
        let timestamp: String = ISO8601DateFormatter().string(from: Date())
        let backupFilename: String = "\(filename)_\(timestamp).\(backupExtension)"
        let backupURL: URL = backupsDirectory.appendingPathComponent(backupFilename)

        try FileManager.default.copyItem(at: url, to: backupURL)

        // Clean up old backups (keep last 10)
        try cleanupOldBackups()
    }

    private func cleanupOldBackups() throws {
        let backupFiles: [URL] = try FileManager.default.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )

        let sortedBackups: [URL] = backupFiles.sorted { (url1, url2) -> Bool in
            let date1: Date? = try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate
            let date2: Date? = try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate
            return (date1 ?? Date.distantPast) > (date2 ?? Date.distantPast)
        }

        // Remove oldest backups, keeping only the latest 10
        for backupToRemove in sortedBackups.dropFirst(10) {
            try? FileManager.default.removeItem(at: backupToRemove)
        }
    }

    // MARK: - Validation

    private func validateConfiguration(_ configuration: BlockConfiguration) throws {
        // Check for required fields
        if configuration.blocks.isEmpty && configuration.connections.isEmpty {
            throw ConfigurationPersistenceError.invalidConfiguration("Configuration is empty")
        }

        // Validate block IDs are unique
        let blockIds: [UUID] = configuration.blocks.map(\.id)
        let uniqueBlockIds: Set<UUID> = Set(blockIds)
        if blockIds.count != uniqueBlockIds.count {
            throw ConfigurationPersistenceError.invalidConfiguration("Duplicate block IDs found")
        }

        // Validate connections reference existing blocks
        for connection in configuration.connections {
            let sourceExists: Bool = configuration.blocks.contains { $0.id == connection.sourceBlockId }
            let targetExists: Bool = configuration.blocks.contains { $0.id == connection.destinationBlockId }

            if !sourceExists {
                throw ConfigurationPersistenceError.invalidConfiguration("Connection references missing source block: \(connection.sourceBlockId)")
            }

            if !targetExists {
                throw ConfigurationPersistenceError.invalidConfiguration("Connection references missing target block: \(connection.destinationBlockId)")
            }
        }

        // Validate parameter values
        for block in configuration.blocks {
            for parameter in block.parameters.values {
                if parameter.value < parameter.minimumValue || parameter.value > parameter.maximumValue {
                    throw ConfigurationPersistenceError.invalidConfiguration("Parameter '\(parameter.name)' value out of range")
                }
            }
        }
    }

    private func validateVersion(_ version: String) throws {
        let supportedVersions: [String] = ["1.0"]
        if !supportedVersions.contains(version) {
            throw ConfigurationPersistenceError.unsupportedVersion(version)
        }
    }

    private func validatePresetCompatibility(_ compatibility: PresetCompatibility) throws {
        // Simple version check for now
        if compatibility.minVersion > currentVersion {
            throw ConfigurationPersistenceError.incompatiblePreset("Preset requires version \(compatibility.minVersion) or higher")
        }
    }

    // MARK: - Format Detection

    private func detectFormat(from url: URL) -> ImportFormat {
        let pathExtension: String = url.pathExtension.lowercased()

        switch pathExtension {
        case "json": return .json
        case "xml": return .xml
        case "preset": return .preset
        case fileExtension: return .json // Our native format is JSON-based
        default: return .json // Default to JSON
        }
    }

    // MARK: - Utility Functions

    private func extractTags(from configuration: BlockConfiguration) -> [String] {
        var tags: [String] = []

        // Add tags based on block types present
        let blockTypes: Set<BlockType> = Set(configuration.blocks.map(\.type))
        for blockType in blockTypes {
            tags.append(blockType.rawValue)
        }

        // Add complexity tag
        if configuration.blocks.count > 10 {
            tags.append("complex")
        } else if configuration.blocks.count > 5 {
            tags.append("intermediate")
        } else {
            tags.append("simple")
        }

        return tags
    }

    private func extractRequiredFeatures(from configuration: BlockConfiguration) -> [String] {
        var features: Set<String> = []

        for block in configuration.blocks {
            switch block.type {
            case .spectrumAnalyzer:
                features.insert("spectrum_analysis")
            case .frequencyModulator:
                features.insert("fm_synthesis")
            case .audioOutput:
                features.insert("audio_output")
            default:
                break
            }
        }

        return Array(features)
    }

    // MARK: - File Browser Integration

    /// Gets the default save location for configurations
    func getDefaultSaveLocation() -> URL {
        return configurationsDirectory
    }

    /// Lists all configuration files in the default directory
    func listConfigurations() throws -> [ConfigurationFileInfo] {
        let files: [URL] = try FileManager.default.contentsOfDirectory(
            at: configurationsDirectory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        )

        return files.compactMap { url in
            guard url.pathExtension == fileExtension else { return nil }

            do {
                let resourceValues: URLResourceValues = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])

                return ConfigurationFileInfo(
                    url: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    createdDate: resourceValues.creationDate ?? Date(),
                    modifiedDate: resourceValues.contentModificationDate ?? Date(),
                    fileSize: Int64(resourceValues.fileSize ?? 0)
                )
            } catch {
                return nil
            }
        }.sorted { $0.modifiedDate > $1.modifiedDate }
    }
}

// MARK: - Data Structures

/// Persistable version of BlockConfiguration with additional metadata
struct PersistableConfiguration: Codable {
    let version: String
    let createdAt: Date
    let modifiedAt: Date
    let metadata: ConfigurationMetadata
    let blocks: [PersistableBlock]
    let connections: [PersistableConnection]

    init(from configuration: BlockConfiguration, version: String) {
        self.version = version
        self.createdAt = configuration.createdDate
        self.modifiedAt = configuration.modifiedDate
        self.metadata = ConfigurationMetadata(
            name: configuration.name,
            description: configuration.metadata["description"] ?? "",
            tags: configuration.metadata["tags"]?.components(separatedBy: ",") ?? [],
            blockCount: configuration.blocks.count,
            connectionCount: configuration.connections.count
        )
        self.blocks = configuration.blocks.map(PersistableBlock.init)
        self.connections = configuration.connections.map(PersistableConnection.init)
    }

    func toConfiguration() throws -> BlockConfiguration {
        let runtimeBlocks: [SignalBlock] = try blocks.map { try $0.toBlock() }
        let runtimeConnections: [Connection] = try connections.map { try $0.toConnection() }

        return BlockConfiguration(
            id: UUID(), // Generate new ID for loaded configuration
            name: metadata.name,
            createdDate: createdAt,
            modifiedDate: modifiedAt,
            blocks: runtimeBlocks,
            connections: runtimeConnections,
            version: version,
            metadata: [
                "description": metadata.description,
                "tags": metadata.tags.joined(separator: ",")
            ]
        )
    }
}

struct ConfigurationMetadata: Codable {
    let name: String
    let description: String
    let tags: [String]
    let blockCount: Int
    let connectionCount: Int
}

struct PersistableBlock: Codable {
    let id: String
    let type: String
    let title: String
    let position: PersistablePoint
    let parameters: [String: PersistableParameter]
    let inputPorts: [String]
    let outputPorts: [String]
    let isActive: Bool

    init(from block: SignalBlock) {
        self.id = block.id.uuidString
        self.type = block.type.rawValue
        self.title = block.title
        self.position = PersistablePoint(from: block.position)
        self.parameters = Dictionary(
            uniqueKeysWithValues: block.parameters.map { key, value in
                (key, PersistableParameter(from: value))
            }
        )
        self.inputPorts = block.inputPorts.map { $0.name }
        self.outputPorts = block.outputPorts.map { $0.name }
        self.isActive = block.isActive
    }

    func toBlock() throws -> SignalBlock {
        guard let blockId = UUID(uuidString: id),
              let blockType = BlockType(rawValue: type) else {
            throw ConfigurationPersistenceError.invalidConfiguration("Invalid block data")
        }

        let runtimeParameters: [String: BlockParameter] = try Dictionary(
            uniqueKeysWithValues: parameters.map { key, value in
                (key, try value.toParameter())
            }
        )

        return SignalBlock(
            id: blockId,
            type: blockType,
            title: title,
            position: position.toPoint(),
            parameters: runtimeParameters,
            inputPorts: blockType.defaultInputPorts,
            outputPorts: blockType.defaultOutputPorts,
            isActive: isActive
        )
    }
}

struct PersistableConnection: Codable {
    let id: String
    let outputBlockId: String
    let outputPort: String
    let inputBlockId: String
    let inputPort: String
    let signalType: String?
    let isActive: Bool

    init(from connection: BlockConnection) {
        self.id = connection.id.uuidString
        self.outputBlockId = connection.outputBlockId.uuidString
        self.outputPort = connection.outputPort
        self.inputBlockId = connection.inputBlockId.uuidString
        self.inputPort = connection.inputPort
        self.signalType = nil // Not used in current implementation
        self.isActive = connection.isActive
    }

    init(from connection: Connection) {
        self.id = connection.id.uuidString
        self.outputBlockId = connection.sourceBlockId.uuidString
        self.outputPort = connection.sourcePort
        self.inputBlockId = connection.destinationBlockId.uuidString
        self.inputPort = connection.destinationPort
        self.signalType = connection.signalType.rawValue
        self.isActive = connection.isActive
    }

    func toConnection() throws -> Connection {
        guard let connectionId = UUID(uuidString: id),
              let sourceId = UUID(uuidString: outputBlockId),
              let targetId = UUID(uuidString: inputBlockId) else {
            throw ConfigurationPersistenceError.invalidConfiguration("Invalid connection data")
        }

        return Connection(
            id: connectionId,
            sourceBlockId: sourceId,
            sourcePort: outputPort,
            destinationBlockId: targetId,
            destinationPort: inputPort,
            signalType: .audio,
            isActive: true
        )
    }
}

struct PersistableParameter: Codable {
    let name: String
    let displayName: String
    let value: Double
    let minimumValue: Double
    let maximumValue: Double
    let unit: String
    let stepSize: Double
    let defaultValue: Double?

    init(from parameter: BlockParameter) {
        self.name = parameter.name
        self.displayName = parameter.displayName
        self.value = parameter.value
        self.minimumValue = parameter.minimumValue
        self.maximumValue = parameter.maximumValue
        self.unit = parameter.unit
        self.stepSize = parameter.stepSize
        self.defaultValue = parameter.value // Use current value as default
    }

    func toParameter() throws -> BlockParameter {
        return BlockParameter(
            name: name,
            displayName: displayName,
            value: value,
            minimumValue: minimumValue,
            maximumValue: maximumValue,
            unit: unit,
            stepSize: stepSize
        )
    }
}

struct PersistablePoint: Codable {
    let xPos: Double
    let yPos: Double

    init(from point: CGPoint) {
        self.xPos = Double(point.x)
        self.yPos = Double(point.y)
    }

    func toPoint() -> CGPoint {
        return CGPoint(x: xPos, y: yPos)
    }
}

struct ExportData: Codable {
    let format: String
    let exportedAt: Date
    let exportedBy: String
    let configuration: PersistableConfiguration
}

struct ConfigurationPreset: Codable {
    let name: String
    let description: String
    let category: String
    let tags: [String]
    let configuration: BlockConfiguration
    let createdAt: Date
    let compatibility: PresetCompatibility
}

struct PresetCompatibility: Codable {
    let minVersion: String
    let maxVersion: String
    let requiredFeatures: [String]
}

struct ConfigurationFileInfo {
    let url: URL
    let name: String
    let createdDate: Date
    let modifiedDate: Date
    let fileSize: Int64

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var relativeModifiedDate: String {
        RelativeDateTimeFormatter().localizedString(for: modifiedDate, relativeTo: Date())
    }
}

// MARK: - Export/Import Formats

enum ExportFormat: String, CaseIterable {
    case json
    case xml
    case preset
    case csv

    var displayName: String {
        switch self {
        case .json: return "JSON"
        case .xml: return "XML"
        case .preset: return "Preset"
        case .csv: return "CSV"
        }
    }

    var fileExtension: String {
        rawValue
    }
}

enum ImportFormat: String, CaseIterable {
    case json
    case xml
    case preset
    case legacy
}

// MARK: - Error Types

enum ConfigurationPersistenceError: Error, LocalizedError {
    case fileNotFound(String)
    case saveFailed(String, String)
    case loadFailed(String, String)
    case invalidConfiguration(String)
    case unsupportedVersion(String)
    case unsupportedFormat(String)
    case invalidFormat(String)
    case incompatiblePreset(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Configuration file not found: \(path)"
        case .saveFailed(let path, let reason):
            return "Failed to save configuration to \(path): \(reason)"
        case .loadFailed(let path, let reason):
            return "Failed to load configuration from \(path): \(reason)"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .unsupportedVersion(let version):
            return "Unsupported configuration version: \(version)"
        case .unsupportedFormat(let format):
            return "Unsupported file format: \(format)"
        case .invalidFormat(let reason):
            return "Invalid file format: \(reason)"
        case .incompatiblePreset(let reason):
            return "Incompatible preset: \(reason)"
        }
    }
}

// MARK: - Export Utilities

class XMLConfigurationExporter {
    func export(_ configuration: BlockConfiguration) -> String {
        var xml: String = """
        <?xml version="1.0" encoding="UTF-8"?>
        <SounderConfiguration version="1.0" created="\(ISO8601DateFormatter().string(from: configuration.createdDate))">
        
        """
        
        // Escape XML special characters
        let escapedName: String = escapeXMLText(configuration.name)
        let escapedDescription: String = escapeXMLText(configuration.metadata["description"] ?? "")

        xml += "\n  <Metadata>"
        xml += "\n    <Name>\(escapedName)</Name>"
        xml += "\n    <Description>\(escapedDescription)</Description>"
        xml += "\n  </Metadata>"

        xml += "\n  <Blocks count=\"\(configuration.blocks.count)\">"
        for block in configuration.blocks {
            let escapedTitle: String = escapeXMLText(block.title)
            xml += "\n    <Block id=\"\(block.id)\" type=\"\(block.type.rawValue)\">"
            xml += "\n      <Title>\(escapedTitle)</Title>"
            xml += "\n      <Position x=\"\(block.position.x)\" y=\"\(block.position.y)\"/>"
            xml += "\n      <Parameters>"
            for parameter in block.parameters.values {
                xml += "\n        <Parameter name=\"\(parameter.name)\" value=\"\(parameter.value)\" min=\"\(parameter.minimumValue)\" max=\"\(parameter.maximumValue)\" unit=\"\(parameter.unit)\"/>"
            }
            xml += "\n      </Parameters>"
            xml += "\n    </Block>"
        }
        xml += "\n  </Blocks>"

        xml += "\n  <Connections count=\"\(configuration.connections.count)\">"
        for connection in configuration.connections {
            xml += "\n    <Connection id=\"\(connection.id)\" from=\"\(connection.sourceBlockId)\" fromPort=\"\(connection.sourcePort)\" to=\"\(connection.destinationBlockId)\" toPort=\"\(connection.destinationPort)\"/>"
        }
        xml += "\n  </Connections>"

        xml += "\n</SounderConfiguration>"

        return xml
    }
    
    private func escapeXMLText(_ text: String) -> String {
        return text.replacingOccurrences(of: "&", with: "&amp;")
                  .replacingOccurrences(of: "\"", with: "&quot;")
                  .replacingOccurrences(of: "'", with: "&apos;")
                  .replacingOccurrences(of: "<", with: "&lt;")
                  .replacingOccurrences(of: ">", with: "&gt;")
    }
}

class CSVConfigurationExporter {
    func export(_ configuration: BlockConfiguration) -> String {
        var csv: String = "Type,ID,Title,Position,Parameters,Status\n"
        
        // Export blocks
        for block in configuration.blocks {
            let params: String = block.parameters.values.map { "\($0.name)=\($0.value)" }.joined(separator: ";")
            csv += "Block,\(block.id),\(block.title),\"(\(block.position.x),\(block.position.y))\",\"\(params)\",\(block.isActive ? "Active" : "Inactive")\n"
        }
        
        // Export connections
        for connection in configuration.connections {
            csv += "Connection,\(connection.id),\(connection.sourceBlockId):\(connection.sourcePort) -> \(connection.destinationBlockId):\(connection.destinationPort),,,\n"
        }

        return csv
    }
}

class XMLConfigurationImporter {
    func `import`(from url: URL) throws -> BlockConfiguration {
        // Simplified XML import - in a full implementation this would use XMLParser
        throw ConfigurationPersistenceError.unsupportedFormat("XML import not yet implemented")
    }
}
