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
        let data: Data = try Data(contentsOf: url)

        guard !data.isEmpty else {
            throw ConfigurationPersistenceError.invalidFormat("Legacy file is empty")
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ConfigurationPersistenceError.invalidFormat("Legacy file is not valid JSON")
        }

        guard let root = jsonObject as? [String: Any] else {
            throw ConfigurationPersistenceError.invalidFormat("Legacy file must contain a JSON object")
        }

        let trimmedName = (root["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String = (trimmedName?.isEmpty == false) ? trimmedName! : url.deletingPathExtension().lastPathComponent

        let legacyDescription: String? = (root["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var metadata: [String: String] = (root["metadata"] as? [String: String]) ?? [:]
        if let legacyDescription, metadata["description"].flatMap({ !$0.isEmpty }) != true {
            metadata["description"] = legacyDescription
        }

        let createdDate: Date = parseLegacyDate(
            root["createdAt"],
            fallbackKeys: ["created", "created_date", "dateCreated"],
            in: root
        ) ?? Date()

        let modifiedDate: Date = parseLegacyDate(
            root["modifiedAt"],
            fallbackKeys: ["updatedAt", "modified", "lastModified"],
            in: root
        ) ?? createdDate

        let legacyBlocks: [[String: Any]] = (root["blocks"] as? [[String: Any]]) ?? []
        var blocks: [SignalBlock] = []
        blocks.reserveCapacity(legacyBlocks.count)

        for blockDict in legacyBlocks {
            guard let typeString = blockDict["type"] as? String,
                  let blockType = BlockType(rawValue: typeString) else {
                continue
            }

            let idString: String? = (blockDict["id"] as? String)
                ?? (blockDict["uuid"] as? String)
                ?? (blockDict["identifier"] as? String)
            let blockId: UUID = idString.flatMap(UUID.init(uuidString:)) ?? UUID()

            let legacyTitle: String? = (blockDict["title"] as? String)
                ?? (blockDict["name"] as? String)
            let positionPoint: CGPoint = parseLegacyPoint(from: blockDict)
            let isActive: Bool = parseLegacyBool(from: blockDict, keys: ["isActive", "active", "enabled"]) ?? true

            var builder: ImportedBlockBuilder = ImportedBlockBuilder(
                id: blockId,
                type: blockType,
                title: legacyTitle ?? "",
                position: positionPoint,
                isActive: isActive
            )

            if let parameterContainer = blockDict["parameters"] as? [String: Any] {
                for (key, value) in parameterContainer {
                    if let parameter = parseLegacyParameter(named: key, rawValue: value) {
                        builder.setParameter(parameter)
                    }
                }
            }

            if let parameterList = blockDict["parameterList"] as? [[String: Any]] {
                for paramDict in parameterList {
                    guard let name = paramDict["name"] as? String else { continue }
                    if let parameter = parseLegacyParameter(named: name, rawValue: paramDict) {
                        builder.setParameter(parameter)
                    }
                }
            }

            do {
                blocks.append(try builder.build())
            } catch {
                throw ConfigurationPersistenceError.invalidFormat("Invalid legacy block data for type \(blockType.rawValue)")
            }
        }

        let blockIdentifiers: Set<UUID> = Set(blocks.map(\.id))

        let legacyConnections: [[String: Any]] = (root["connections"] as? [[String: Any]]) ?? []
        var connections: [Connection] = []
        connections.reserveCapacity(legacyConnections.count)

        for connectionDict in legacyConnections {
            guard let sourceId = parseLegacyUUID(from: connectionDict, keys: ["fromBlockId", "sourceBlockId", "from", "source"]),
                  let destinationId = parseLegacyUUID(from: connectionDict, keys: ["toBlockId", "destinationBlockId", "to", "destination"]),
                  sourceId != destinationId,
                  blockIdentifiers.contains(sourceId),
                  blockIdentifiers.contains(destinationId) else {
                continue
            }

            guard let sourcePort = parseLegacyString(from: connectionDict, keys: ["fromPort", "sourcePort", "outputPort"]),
                  let destinationPort = parseLegacyString(from: connectionDict, keys: ["toPort", "destinationPort", "inputPort"]),
                  !sourcePort.isEmpty,
                  !destinationPort.isEmpty else {
                continue
            }

            let connectionId: UUID = parseLegacyUUID(from: connectionDict, keys: ["id", "identifier", "uuid"]) ?? UUID()
            let signalTypeString: String? = parseLegacyString(from: connectionDict, keys: ["signalType", "type", "kind"])
            let signalType: SignalType = signalTypeString.flatMap { SignalType(rawValue: $0.lowercased()) } ?? .audio
            let isActive: Bool = parseLegacyBool(from: connectionDict, keys: ["isActive", "active"]) ?? true

            connections.append(
                Connection(
                    id: connectionId,
                    sourceBlockId: sourceId,
                    sourcePort: sourcePort,
                    destinationBlockId: destinationId,
                    destinationPort: destinationPort,
                    signalType: signalType,
                    isActive: isActive
                )
            )
        }

        let trimmedVersion = (root["version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let version: String = (trimmedVersion?.isEmpty == false) ? trimmedVersion! : currentVersion

        return BlockConfiguration(
            id: UUID(),
            name: name,
            createdDate: createdDate,
            modifiedDate: max(modifiedDate, createdDate),
            blocks: blocks,
            connections: connections,
            version: version,
            metadata: metadata
        )
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

// MARK: - Import Helpers

struct ImportedParameterData {
    let name: String
    let displayName: String?
    let value: Double?
    let minimum: Double?
    let maximum: Double?
    let unit: String?
    let step: Double?

    func makeParameter(defaultParameter: BlockParameter?) -> BlockParameter {
        let base: BlockParameter? = defaultParameter
        let resolvedDisplayName: String = displayName ?? base?.displayName ?? displayNameForParameter(name)
        let defaults = inferredRange(for: name, expectedValue: value)
        let minValue: Double = minimum ?? base?.minimumValue ?? defaults.min
        let maxValue: Double = maximum ?? base?.maximumValue ?? defaults.max
        let unitValue: String = unit ?? base?.unit ?? defaults.unit
        let isLogarithmic: Bool = base?.isLogarithmic ?? defaults.isLog
        let orderedMin: Double = min(minValue, maxValue)
        let orderedMax: Double = max(minValue, maxValue)
        let stepCandidate: Double = step ?? base?.stepSize ?? inferredStepSize(min: orderedMin, max: orderedMax)
        let stepSize: Double = max(stepCandidate, 0.0001)
        let defaultValue: Double = value ?? base?.value ?? (orderedMin + orderedMax) / 2.0
        let clampedValue: Double = min(max(defaultValue, orderedMin), orderedMax)

        return BlockParameter(
            name: name,
            displayName: resolvedDisplayName,
            value: clampedValue,
            minimumValue: orderedMin,
            maximumValue: orderedMax,
            unit: unitValue,
            stepSize: stepSize,
            isLogarithmic: isLogarithmic
        )
    }
}

struct ImportedBlockBuilder {
    let id: UUID
    let type: BlockType
    var title: String
    var position: CGPoint
    var isActive: Bool
    private var parameterOverrides: [String: ImportedParameterData] = [:]

    init(id: UUID, type: BlockType, title: String, position: CGPoint, isActive: Bool) {
        self.id = id
        self.type = type
        self.title = title
        self.position = position
        self.isActive = isActive
    }

    mutating func setParameter(_ parameter: ImportedParameterData) {
        parameterOverrides[parameter.name] = parameter
    }

    func build() throws -> SignalBlock {
        var parameters: [String: BlockParameter] = type.createDefaultParameters()

        for (name, override) in parameterOverrides {
            parameters[name] = override.makeParameter(defaultParameter: parameters[name])
        }

        for required in type.requiredParameters where parameters[required] == nil {
            parameters[required] = fallbackParameter(named: required)
        }

        let resolvedTitle: String = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle: String = resolvedTitle.isEmpty ? type.displayName : resolvedTitle
        let sanitizedPosition: CGPoint = CGPoint(
            x: sanitizeCoordinate(position.x),
            y: sanitizeCoordinate(position.y)
        )

        return SignalBlock(
            id: id,
            type: type,
            title: finalTitle,
            position: sanitizedPosition,
            parameters: parameters,
            inputPorts: type.defaultInputPorts,
            outputPorts: type.defaultOutputPorts,
            isActive: isActive
        )
    }
}

private func fallbackParameter(named name: String) -> BlockParameter {
    let lowerName: String = name.lowercased()

    if lowerName.contains("frequency") {
        return .frequency(name: name, displayName: displayNameForParameter(name))
    } else if lowerName.contains("gain") || lowerName.contains("amplitude") {
        return .amplitude(name: name, displayName: displayNameForParameter(name))
    } else if lowerName.contains("time") || lowerName.contains("duration") || lowerName.contains("window") {
        return .time(name: name, displayName: displayNameForParameter(name), value: 0.1, minTime: 0.0, maxTime: 10.0)
    } else if lowerName.contains("depth") || lowerName.contains("mix") || lowerName.contains("percentage") {
        return .percentage(name: name, displayName: displayNameForParameter(name))
    }

    return BlockParameter(
        name: name,
        displayName: displayNameForParameter(name),
        value: 0.0,
        minimumValue: 0.0,
        maximumValue: 1.0,
        unit: "",
        stepSize: 0.1
    )
}

private func sanitizeCoordinate(_ value: Double) -> Double {
    guard value.isFinite else { return 0.0 }
    return max(0.0, value)
}

private func displayNameForParameter(_ name: String) -> String {
    let cleaned: String = name.replacingOccurrences(of: "_", with: " ")
    let parts: [Substring] = cleaned.split(whereSeparator: { !$0.isLetter && !$0.isNumber })

    guard !parts.isEmpty else {
        return name.capitalized
    }

    return parts.map { part -> String in
        let lower = part.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }.joined(separator: " ")
}

private func inferredRange(for name: String, expectedValue: Double?) -> (min: Double, max: Double, unit: String, isLog: Bool) {
    let lower: String = name.lowercased()

    if lower.contains("frequency") {
        return (20.0, 20000.0, "Hz", true)
    } else if lower.contains("gain") || lower.contains("amplitude") {
        return (-60.0, 6.0, "dB", false)
    } else if lower.contains("depth") || lower.contains("mix") || lower.contains("amount") || lower.contains("percentage") {
        return (0.0, 100.0, "%", false)
    } else if lower.contains("time") || lower.contains("duration") || lower.contains("window") {
        let value: Double = expectedValue ?? 1.0
        return (0.0, max(value * 4.0, 1.0), "s", false)
    } else if lower.contains("qfactor") || lower.contains("resonance") {
        return (0.1, 10.0, "", false)
    }

    let fallbackValue: Double = expectedValue ?? 1.0
    return (0.0, max(fallbackValue, 1.0), "", false)
}

private func inferredStepSize(min: Double, max: Double) -> Double {
    let range: Double = max - min
    if range <= 0 { return 0.1 }
    let candidate: Double = range / 100.0
    if candidate >= 1.0 {
        return round(candidate)
    }
    if candidate >= 0.1 {
        return 0.1
    }
    return Swift.max(candidate, 0.01)
}

private func parseLegacyDate(_ primaryValue: Any?, fallbackKeys: [String], in container: [String: Any]) -> Date? {
    if let date = convertToDate(primaryValue) {
        return date
    }

    for key in fallbackKeys {
        if let match = container[key], let date = convertToDate(match) {
            return date
        }
    }

    return nil
}

private func convertToDate(_ value: Any?) -> Date? {
    switch value {
    case let date as Date:
        return date
    case let number as NSNumber:
        return Date(timeIntervalSince1970: number.doubleValue)
    case let double as Double:
        return Date(timeIntervalSince1970: double)
    case let string as String:
        let trimmed: String = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let isoFormatter: ISO8601DateFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }

        let fallbackFormats: [String] = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"]
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in fallbackFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return nil
    default:
        return nil
    }
}

private func parseLegacyPoint(from container: [String: Any]) -> CGPoint {
    if let nested = container["position"] as? [String: Any] {
        return parseLegacyPointValues(in: nested)
    }
    return parseLegacyPointValues(in: container)
}

private func parseLegacyPointValues(in container: [String: Any]) -> CGPoint {
    let x: Double = parseLegacyDouble(from: container, keys: ["x", "xPos", "posX", "left"]) ?? 0.0
    let y: Double = parseLegacyDouble(from: container, keys: ["y", "yPos", "posY", "top"]) ?? 0.0
    return CGPoint(x: sanitizeCoordinate(x), y: sanitizeCoordinate(y))
}

private func parseLegacyBool(from container: [String: Any], keys: [String]) -> Bool? {
    for key in keys {
        if let value = container[key] {
            if let bool = value as? Bool {
                return bool
            }
            if let number = value as? NSNumber {
                return number.intValue != 0
            }
            if let string = value as? String {
                let lower = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["true", "yes", "1"].contains(lower) {
                    return true
                }
                if ["false", "no", "0"].contains(lower) {
                    return false
                }
            }
        }
    }
    return nil
}

private func parseLegacyUUID(from container: [String: Any], keys: [String]) -> UUID? {
    for key in keys {
        if let stringValue = container[key] as? String,
           let uuid = UUID(uuidString: stringValue) {
            return uuid
        }
    }
    return nil
}

private func parseLegacyString(from container: [String: Any], keys: [String]) -> String? {
    for key in keys {
        if let stringValue = container[key] as? String {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
    }
    return nil
}

private func parseLegacyDouble(from container: [String: Any], keys: [String]) -> Double? {
    for key in keys {
        if let value = container[key],
           let parsed = asDouble(value) {
            return parsed
        }
    }
    return nil
}

private func asDouble(_ value: Any?) -> Double? {
    switch value {
    case let double as Double:
        return double
    case let int as Int:
        return Double(int)
    case let int64 as Int64:
        return Double(int64)
    case let float as Float:
        return Double(float)
    case let number as NSNumber:
        return number.doubleValue
    case let string as String:
        let trimmed: String = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(trimmed)
    default:
        return nil
    }
}

private func parseLegacyParameter(named name: String, rawValue: Any) -> ImportedParameterData? {
    if let dictionary = rawValue as? [String: Any] {
        let value = asDouble(dictionary["value"]) ?? asDouble(dictionary["current"])
        let minimum = asDouble(dictionary["minimum"]) ?? asDouble(dictionary["min"]) ?? asDouble(dictionary["lower"])
        let maximum = asDouble(dictionary["maximum"]) ?? asDouble(dictionary["max"]) ?? asDouble(dictionary["upper"])
        let unit = dictionary["unit"] as? String
        let step = asDouble(dictionary["step"]) ?? asDouble(dictionary["stepSize"])
        let displayName = dictionary["displayName"] as? String ?? dictionary["label"] as? String

        return ImportedParameterData(
            name: name,
            displayName: displayName,
            value: value,
            minimum: minimum,
            maximum: maximum,
            unit: unit,
            step: step
        )
    }

    if let directValue = asDouble(rawValue) {
        return ImportedParameterData(
            name: name,
            displayName: nil,
            value: directValue,
            minimum: nil,
            maximum: nil,
            unit: nil,
            step: nil
        )
    }

    return nil
}

private func parseDouble(from string: String?) -> Double? {
    guard let string else { return nil }
    return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
}

private func parseBool(from string: String?) -> Bool? {
    guard let string else { return nil }
    let lower = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if ["true", "yes", "1"].contains(lower) {
        return true
    }
    if ["false", "no", "0"].contains(lower) {
        return false
    }
    return nil
}

// MARK: - XML Importer

class XMLConfigurationImporter: NSObject, XMLParserDelegate {
    private var configurationName: String?
    private var configurationDescription: String?
    private var configurationVersion: String?
    private var createdDate: Date?
    private var blocks: [SignalBlock] = []
    private var connections: [Connection] = []
    private var currentBlock: ImportedBlockBuilder?
    private var currentElement: String?
    private var accumulatedCharacters: String = ""
    private var parseError: Error?

    func `import`(from url: URL) throws -> BlockConfiguration {
        resetState()

        let data: Data = try Data(contentsOf: url)
        let parser: XMLParser = XMLParser(data: data)
        parser.delegate = self

        if parser.parse(), parseError == nil {
            let blockIds: Set<UUID> = Set(blocks.map(\.id))
            let filteredConnections: [Connection] = connections.filter { connection in
                blockIds.contains(connection.sourceBlockId) && blockIds.contains(connection.destinationBlockId)
            }

            let trimmedConfigName = configurationName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name: String = (trimmedConfigName?.isEmpty == false) ? trimmedConfigName! : url.deletingPathExtension().lastPathComponent

            var metadata: [String: String] = [:]
            if let description = configurationDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                metadata["description"] = description
            }

            let created: Date = createdDate ?? Date()
            let modified: Date = Date()
            let finalModified: Date = modified < created ? created : modified

            return BlockConfiguration(
                id: UUID(),
                name: name,
                createdDate: created,
                modifiedDate: finalModified,
                blocks: blocks,
                connections: filteredConnections,
                version: configurationVersion ?? "1.0",
                metadata: metadata
            )
        }

        if let parseError {
            throw parseError
        }

        throw ConfigurationPersistenceError.invalidFormat("Unable to parse XML configuration")
    }

    private func resetState() {
        configurationName = nil
        configurationDescription = nil
        configurationVersion = nil
        createdDate = nil
        blocks = []
        connections = []
        currentBlock = nil
        currentElement = nil
        accumulatedCharacters = ""
        parseError = nil
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        currentElement = elementName
        accumulatedCharacters = ""

        switch elementName {
        case "SounderConfiguration":
            configurationVersion = attributeDict["version"]
            if let createdString = attributeDict["created"], let date = convertToDate(createdString) {
                createdDate = date
            }
        case "Block":
            guard let typeString = attributeDict["type"],
                  let blockType = BlockType(rawValue: typeString) else {
                parseError = ConfigurationPersistenceError.invalidFormat("Unknown block type in XML")
                parser.abortParsing()
                return
            }

            let blockId: UUID = attributeDict["id"].flatMap(UUID.init(uuidString:)) ?? UUID()
            let isActive: Bool = attributeDict["active"].flatMap(parseBool) ?? attributeDict["isActive"].flatMap(parseBool) ?? true

            currentBlock = ImportedBlockBuilder(
                id: blockId,
                type: blockType,
                title: "",
                position: .zero,
                isActive: isActive
            )
        case "Position":
            guard var builder = currentBlock else { return }
            let x: Double = parseDouble(from: attributeDict["x"]) ?? 0.0
            let y: Double = parseDouble(from: attributeDict["y"]) ?? 0.0
            builder.position = CGPoint(x: x, y: y)
            currentBlock = builder
        case "Parameter":
            guard var builder = currentBlock,
                  let name = attributeDict["name"] else { return }

            let parameter = ImportedParameterData(
                name: name,
                displayName: attributeDict["displayName"],
                value: parseDouble(from: attributeDict["value"]),
                minimum: parseDouble(from: attributeDict["min"]) ?? parseDouble(from: attributeDict["minimum"]),
                maximum: parseDouble(from: attributeDict["max"]) ?? parseDouble(from: attributeDict["maximum"]),
                unit: attributeDict["unit"],
                step: parseDouble(from: attributeDict["step"]) ?? parseDouble(from: attributeDict["stepSize"])
            )
            builder.setParameter(parameter)
            currentBlock = builder
        case "Connection":
            guard let sourceIdString = attributeDict["from"],
                  let destinationIdString = attributeDict["to"],
                  let sourceId = UUID(uuidString: sourceIdString),
                  let destinationId = UUID(uuidString: destinationIdString),
                  let sourcePort = attributeDict["fromPort"],
                  let destinationPort = attributeDict["toPort"],
                  !sourcePort.isEmpty,
                  !destinationPort.isEmpty,
                  sourceId != destinationId else {
                return
            }

            let connectionId: UUID = attributeDict["id"].flatMap(UUID.init(uuidString:)) ?? UUID()
            let signalType: SignalType = attributeDict["signalType"].flatMap { SignalType(rawValue: $0.lowercased()) } ?? .audio

            let connection = Connection(
                id: connectionId,
                sourceBlockId: sourceId,
                sourcePort: sourcePort,
                destinationBlockId: destinationId,
                destinationPort: destinationPort,
                signalType: signalType,
                isActive: true
            )
            connections.append(connection)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let text: String = accumulatedCharacters.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "Name":
            configurationName = text
        case "Description":
            configurationDescription = text
        case "Title":
            if var builder = currentBlock {
                builder.title = text
                currentBlock = builder
            }
        case "Block":
            guard let builder = currentBlock else { break }
            do {
                blocks.append(try builder.build())
            } catch {
                parseError = error
                parser.abortParsing()
            }
            currentBlock = nil
        default:
            break
        }

        accumulatedCharacters = ""
        currentElement = nil
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        accumulatedCharacters.append(string)
    }
}
