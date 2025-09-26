import SwiftUI
import Combine
import UniformTypeIdentifiers

/// View model for configuration save/load operations and file management
@MainActor
class ConfigurationViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var currentConfiguration: BlockConfiguration?
    @Published var hasUnsavedChanges: Bool = false
    @Published var currentFileURL: URL?
    @Published var isLoading: Bool = false
    @Published var isSaving: Bool = false

    // File operations
    @Published var showingFilePicker: Bool = false
    @Published var showingSaveDialog: Bool = false
    @Published var filePickerMode: FilePickerMode = .load

    // Recent files
    @Published var recentFiles: [RecentFile] = []
    @Published var showingRecentFiles: Bool = false

    // Import/Export
    @Published var showingExportOptions: Bool = false
    @Published var exportFormat: ExportFormat = .json

    // Error handling
    @Published var errorMessage: String?
    @Published var showingError: Bool = false

    // MARK: - Services

    private let blockManager: BlockManagerService
    private var cancellables: Set<AnyCancellable> = Set<AnyCancellable>()
    private var autoSaveCancellable: AnyCancellable?

    // MARK: - File Management

    private let configurationDirectory: URL
    private let recentFilesKey: String = "RecentConfigurationFiles"
    private let maxRecentFiles: Int = 10

    // MARK: - Initialization

    init(blockManager: BlockManagerService) {
        self.blockManager = blockManager

        // Set up configuration directory
        let documentsURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        configurationDirectory = documentsURL.appendingPathComponent("Sounder Configurations")

        setupDirectory()
        loadRecentFiles()
        setupBindings()
    }

    private func setupDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: configurationDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            print("Failed to create configuration directory: \(error)")
        }
    }

    private func setupBindings() {
        // Monitor configuration changes
        Timer.publish(every: 1.0, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.checkForChanges()
                }
            }
            .store(in: &cancellables)
    }

    private func checkForChanges() async {
        let newConfiguration: BlockConfiguration = await blockManager.getCurrentConfiguration()

        if let current = currentConfiguration {
            hasUnsavedChanges = !areConfigurationsEqual(current, newConfiguration)
        } else {
            hasUnsavedChanges = !newConfiguration.blocks.isEmpty || !newConfiguration.connections.isEmpty
        }

        currentConfiguration = newConfiguration
    }

    private func areConfigurationsEqual(_ config1: BlockConfiguration, _ config2: BlockConfiguration) -> Bool {
        // Compare blocks
        if config1.blocks.count != config2.blocks.count {
            return false
        }

        for block1 in config1.blocks {
            guard let block2 = config2.blocks.first(where: { $0.id == block1.id }) else {
                return false
            }

            if !areBlocksEqual(block1, block2) {
                return false
            }
        }

        // Compare connections
        if config1.connections.count != config2.connections.count {
            return false
        }

        for connection1 in config1.connections {
            guard config2.connections.contains(where: { $0.id == connection1.id }) else {
                return false
            }
        }

        return true
    }

    private func areBlocksEqual(_ block1: SignalBlock, _ block2: SignalBlock) -> Bool {
        return block1.id == block2.id &&
               block1.type == block2.type &&
               block1.position == block2.position &&
               block1.parameters.count == block2.parameters.count
    }

    // MARK: - Save Operations

    func saveConfiguration() async {
        if let currentURL = currentFileURL {
            await saveConfiguration(to: currentURL)
        } else {
            await saveConfigurationAs()
        }
    }

    func saveConfigurationAs() async {
        showingSaveDialog = true
        filePickerMode = .save
    }

    func saveConfiguration(to url: URL) async {
        guard let configuration = currentConfiguration else { return }

        isSaving = true

        do {
            try await blockManager.saveConfiguration(to: url)

            currentFileURL = url
            hasUnsavedChanges = false
            addToRecentFiles(url)

            print("Configuration saved to: \(url.path)")

        } catch {
            await handleError(error, context: "saving configuration")
        }

        isSaving = false
    }

    func saveConfigurationWithName(_ name: String) async {
        let fileName: String = name.hasSuffix(".sounder") ? name : "\(name).sounder"
        let url: URL = configurationDirectory.appendingPathComponent(fileName)
        await saveConfiguration(to: url)
    }

    // MARK: - Load Operations

    func loadConfiguration() async {
        showingFilePicker = true
        filePickerMode = .load
    }

    func loadConfiguration(from url: URL) async {
        isLoading = true

        do {
            let configuration: BlockConfiguration = try await blockManager.loadConfiguration(from: url)

            currentConfiguration = configuration
            currentFileURL = url
            hasUnsavedChanges = false
            addToRecentFiles(url)

            print("Configuration loaded from: \(url.path)")

        } catch {
            await handleError(error, context: "loading configuration")
        }

        isLoading = false
    }

    func loadRecentFile(_ recentFile: RecentFile) async {
        await loadConfiguration(from: recentFile.url)
    }

    // MARK: - New Configuration

    func newConfiguration() async {
        if hasUnsavedChanges {
            // In a real app, show confirmation dialog
            // For now, proceed without saving
        }

        await blockManager.clearConfiguration()
        currentConfiguration = await blockManager.getCurrentConfiguration()
        currentFileURL = nil
        hasUnsavedChanges = false
    }

    func reset() {
        currentConfiguration = nil
        currentFileURL = nil
        hasUnsavedChanges = false
    }

    // MARK: - Recent Files Management

    private func loadRecentFiles() {
        let defaults: UserDefaults = UserDefaults.standard
        if let data = defaults.data(forKey: recentFilesKey),
           let recentFiles: [RecentFile] = try? JSONDecoder().decode([RecentFile].self, from: data) {
            self.recentFiles = recentFiles.filter { $0.url.isFileURL && FileManager.default.fileExists(atPath: $0.url.path) }
        }
    }

    private func saveRecentFiles() {
        let defaults: UserDefaults = UserDefaults.standard
        if let data: Data = try? JSONEncoder().encode(recentFiles) {
            defaults.set(data, forKey: recentFilesKey)
        }
    }

    private func addToRecentFiles(_ url: URL) {
        let recentFile: RecentFile = RecentFile(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            lastOpened: Date()
        )

        // Remove existing entry
        recentFiles.removeAll { $0.url == url }

        // Add to beginning
        recentFiles.insert(recentFile, at: 0)

        // Limit to max recent files
        if recentFiles.count > maxRecentFiles {
            recentFiles = Array(recentFiles.prefix(maxRecentFiles))
        }

        saveRecentFiles()
    }

    func removeFromRecentFiles(_ recentFile: RecentFile) {
        recentFiles.removeAll { $0.id == recentFile.id }
        saveRecentFiles()
    }

    func clearRecentFiles() {
        recentFiles.removeAll()
        saveRecentFiles()
    }

    // MARK: - Import/Export

    func exportConfiguration(format: ExportFormat, to url: URL) async {
        guard let configuration = currentConfiguration else { return }

        do {
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

            print("Configuration exported to: \(url.path)")

        } catch {
            await handleError(error, context: "exporting configuration")
        }
    }

    private func exportAsJSON(_ configuration: BlockConfiguration, to url: URL) async throws {
        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data: Data = try encoder.encode(configuration)
        try data.write(to: url)
    }

    private func exportAsXML(_ configuration: BlockConfiguration, to url: URL) async throws {
        // Simplified XML export
        var xml: String = """
        <?xml version="1.0" encoding="UTF-8"?>
        <SounderConfiguration version="1.0">
        """

        xml += "\n  <Blocks>"
        for block in configuration.blocks {
            let escapedTitle = block.title.replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;").replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            xml += "\n    <Block id=\"\(block.id)\" type=\"\(block.type.rawValue)\" title=\"\(escapedTitle)\">"
            xml += "\n      <Position x=\"\(block.position.x)\" y=\"\(block.position.y)\"/>"
            xml += "\n      <Parameters>"
            for (name, parameter) in block.parameters {
                xml += "\n        <Parameter name=\"\(name)\" value=\"\(parameter.value)\"/>"
            }
            xml += "\n      </Parameters>"
            xml += "\n    </Block>"
        }
        xml += "\n  </Blocks>"

        xml += "\n  <Connections>"
        for connection in configuration.connections {
            xml += "\n    <Connection id=\"\(connection.id)\" source=\"\(connection.sourceBlockId)\" target=\"\(connection.destinationBlockId)\"/>"
        }
        xml += "\n  </Connections>"

        xml += "\n</SounderConfiguration>"

        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportAsPreset(_ configuration: BlockConfiguration, to url: URL) async throws {
        // Export as a preset (simplified JSON with metadata)
        struct Preset: Codable {
            let name: String
            let description: String
            let category: String
            let configuration: BlockConfiguration
            let createdAt: Date
        }

        let preset: Preset = Preset(
            name: url.deletingPathExtension().lastPathComponent,
            description: "Exported from Sounder",
            category: "User Presets",
            configuration: configuration,
            createdAt: Date()
        )

        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601

        let data: Data = try encoder.encode(preset)
        try data.write(to: url)
    }

    private func exportAsCSV(_ configuration: BlockConfiguration, to url: URL) async throws {
        // Export as CSV format for spreadsheet analysis
        var csvContent: String = "BlockID,BlockType,Title,PositionX,PositionY,ParameterCount\n"

        for block in configuration.blocks {
            csvContent += "\(block.id),\(block.type.rawValue),\(block.title),\(block.position.x),\(block.position.y),\(block.parameters.count)\n"
        }

        csvContent += "\nConnectionID,SourceBlockID,SourcePort,DestinationBlockID,DestinationPort,SignalType\n"
        for connection in configuration.connections {
            csvContent += "\(connection.id),\(connection.sourceBlockId),\(connection.sourcePort),\(connection.destinationBlockId),\(connection.destinationPort),\(connection.signalType.rawValue)\n"
        }

        try csvContent.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - File Operations UI

    func showRecentFiles() {
        showingRecentFiles = true
    }

    func hideRecentFiles() {
        showingRecentFiles = false
    }

    func showExportOptions() {
        showingExportOptions = true
    }

    func hideExportOptions() {
        showingExportOptions = false
    }

    // MARK: - Configuration Templates

    func getAvailableTemplates() -> [ConfigurationTemplate] {
        return ConfigurationTemplate.allTemplates
    }

    func createFromTemplate(_ template: ConfigurationTemplate) async {
        await newConfiguration()

        // Create blocks according to template
        var createdBlocks: [UUID: SignalBlock] = [:]

        for templateBlock in template.blocks {
            do {
                let block: SignalBlock = try await blockManager.createBlock(
                    type: templateBlock.type,
                    at: templateBlock.position
                )

                // Set parameters
                for (paramName, value) in templateBlock.parameters {
                    try await blockManager.updateBlockParameter(
                        blockId: block.id,
                        parameterName: paramName,
                        value: value
                    )
                }

                createdBlocks[templateBlock.templateId] = block

            } catch {
                await handleError(error, context: "creating template block")
                return
            }
        }

        // Create connections
        for templateConnection in template.connections {
            guard let sourceBlock = createdBlocks[templateConnection.sourceTemplateId],
                  let targetBlock = createdBlocks[templateConnection.targetTemplateId] else {
                continue
            }

            do {
                let _ = try await blockManager.createConnection(
                    from: sourceBlock.id,
                    sourcePort: templateConnection.sourcePort,
                    to: targetBlock.id,
                    destinationPort: templateConnection.targetPort
                )
            } catch {
                await handleError(error, context: "creating template connection")
            }
        }

        hasUnsavedChanges = true
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error, context: String) async {
        let message: String = "Error \(context): \(error.localizedDescription)"
        print(message)

        errorMessage = message
        showingError = true
    }

    func dismissError() {
        showingError = false
        errorMessage = nil
    }

    // MARK: - Validation

    func validateConfiguration(_ configuration: BlockConfiguration) -> ConfigurationValidationResult {
        var warnings: [String] = []
        var errors: [String] = []

        // Check for orphaned blocks
        let connectedBlockIds: Set<UUID> = Set(configuration.connections.flatMap { [$0.destinationBlockId, $0.sourceBlockId] })
        let orphanedBlocks: [SignalBlock] = configuration.blocks.filter { !connectedBlockIds.contains($0.id) }

        if !orphanedBlocks.isEmpty {
            warnings.append("Found \(orphanedBlocks.count) unconnected blocks")
        }

        // Check for missing output blocks
        let hasOutputBlock: Bool = configuration.blocks.contains { $0.type == .audioOutput }
        if !hasOutputBlock && !configuration.blocks.isEmpty {
            warnings.append("No audio output block found - no sound will be produced")
        }

        // Check for invalid connections
        for connection in configuration.connections {
            let sourceBlock: SignalBlock? = configuration.blocks.first { $0.id == connection.sourceBlockId }
            let targetBlock: SignalBlock? = configuration.blocks.first { $0.id == connection.destinationBlockId }

            if sourceBlock == nil {
                errors.append("Connection references missing source block")
            }

            if targetBlock == nil {
                errors.append("Connection references missing target block")
            }
        }

        return ConfigurationValidationResult(
            isValid: errors.isEmpty,
            warnings: warnings,
            errors: errors
        )
    }

    // MARK: - Auto-save

    func setAutoSaveEnabled(_ isEnabled: Bool) {
        autoSaveCancellable?.cancel()
        autoSaveCancellable = nil

        guard isEnabled else { return }

        autoSaveCancellable = Timer.publish(every: 30.0, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.autoSave()
                }
            }
    }

    private func autoSave() async {
        guard hasUnsavedChanges,
              let currentURL = currentFileURL else { return }

        // Create backup first
        let backupURL: URL = currentURL.appendingPathExtension("backup")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.copyItem(at: currentURL, to: backupURL)

        // Auto-save
        await saveConfiguration(to: currentURL)
    }
}

// MARK: - Supporting Types

struct RecentFile: Codable, Identifiable {
    let id: UUID = UUID()
    let url: URL
    let name: String
    let lastOpened: Date

    var displayName: String {
        return name
    }

    var relativeTime: String {
        let formatter: RelativeDateTimeFormatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: lastOpened, relativeTo: Date())
    }
}

enum FilePickerMode {
    case load
    case save
    case export
}

// ExportFormat is defined in ConfigurationPersistenceService.swift

struct ConfigurationValidationResult {
    let isValid: Bool
    let warnings: [String]
    let errors: [String]

    var hasIssues: Bool {
        !warnings.isEmpty || !errors.isEmpty
    }
}

// MARK: - Configuration Templates

struct ConfigurationTemplate {
    let id: UUID = UUID()
    let name: String
    let description: String
    let category: String
    let blocks: [TemplateBlock]
    let connections: [TemplateConnection]

    static let allTemplates: [ConfigurationTemplate] = [
        ConfigurationTemplate(
            name: "Simple Sine Wave",
            description: "Basic sine wave generator with output",
            category: "Basic",
            blocks: [
                TemplateBlock(
                    templateId: UUID(),
                    type: .sineOscillator,
                    position: CGPoint(x: 100, y: 100),
                    parameters: ["frequency": 440.0, "amplitude": -12.0]
                ),
                TemplateBlock(
                    templateId: UUID(),
                    type: .audioOutput,
                    position: CGPoint(x: 300, y: 100),
                    parameters: [:]
                )
            ],
            connections: [
                TemplateConnection(
                    sourceTemplateId: UUID(),
                    sourcePort: "signal",
                    targetTemplateId: UUID(),
                    targetPort: "input"
                )
            ]
        ),

        ConfigurationTemplate(
            name: "FM Synthesis",
            description: "Frequency modulated sine wave",
            category: "Synthesis",
            blocks: [
                TemplateBlock(
                    templateId: UUID(),
                    type: .sineOscillator,
                    position: CGPoint(x: 100, y: 100),
                    parameters: ["frequency": 10000.0]
                ),
                TemplateBlock(
                    templateId: UUID(),
                    type: .triangleOscillator,
                    position: CGPoint(x: 100, y: 200),
                    parameters: ["frequency": 100.0]
                ),
                TemplateBlock(
                    templateId: UUID(),
                    type: .frequencyModulator,
                    position: CGPoint(x: 300, y: 150),
                    parameters: ["deviation": 3000.0]
                ),
                TemplateBlock(
                    templateId: UUID(),
                    type: .audioOutput,
                    position: CGPoint(x: 500, y: 150),
                    parameters: [:]
                )
            ],
            connections: []
        )
    ]
}

struct TemplateBlock {
    let templateId: UUID
    let type: BlockType
    let position: CGPoint
    let parameters: [String: Double]
}

struct TemplateConnection {
    let sourceTemplateId: UUID
    let sourcePort: String
    let targetTemplateId: UUID
    let targetPort: String
}
