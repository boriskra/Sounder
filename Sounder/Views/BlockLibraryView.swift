import SwiftUI
import UniformTypeIdentifiers

/// Block library view for browsing and adding signal processing blocks
/// Organized by categories with search, templates, and drag-and-drop support
struct BlockLibraryView: View {
    @ObservedObject var blockManager: BlockManagerServiceImpl
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedCategory: LibraryCategory = .all
    @State private var selectedTemplate: BlockTemplate?
    @State private var showingTemplateDetail = false
    @State private var templates: [BlockTemplate] = BlockTemplate.loadAll()
    @State private var showingTemplateCreation = false
    @State private var templateError: String?

    private let gridColumns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)
    ]

    var body: some View {
        NavigationSplitView {
            // Category sidebar
            categorySidebar
        } detail: {
            // Main content
            VStack(spacing: 0) {
                // Header
                libraryHeader

                // Search bar
                searchBar

                // Block grid
                blockGridView

                // Template section
                if !filteredTemplates.isEmpty {
                    templateSection
                }
            }
        }
        .navigationTitle("Block Library")
        .frame(minWidth: 600, minHeight: 400)
        .sheet(isPresented: $showingTemplateDetail) {
            if let template = selectedTemplate {
                TemplateDetailView(
                    template: template,
                    blockManager: blockManager,
                    onDismiss: { dismiss() },
                    onDelete: template.isBuiltIn ? nil : { deleteTemplate($0) }
                )
            }
        }
        .sheet(isPresented: $showingTemplateCreation) {
            TemplateCreationView(existingNames: templates.map { $0.name }) { name, description in
                await createTemplate(name: name, description: description)
            }
        }
        .alert("Template Error", isPresented: Binding(
            get: { templateError != nil },
            set: { if !$0 { templateError = nil } }
        )) {
            Button("OK", role: .cancel) { templateError = nil }
        } message: {
            Text(templateError ?? "")
        }
        .onAppear { reloadTemplates() }
    }

    // MARK: - Category Sidebar

    private var categorySidebar: some View {
        List(LibraryCategory.allCases, id: \.self, selection: $selectedCategory) { category in
            HStack {
                Image(systemName: category.icon)
                    .foregroundColor(category.color)
                    .frame(width: 20)

                Text(category.displayName)

                Spacer()

                Text("\(filteredBlocks(for: category).count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }

    // MARK: - Library Header

    private var libraryHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Signal Processing Blocks")
                    .font(.title2.bold())

                Text("\(filteredBlocks.count) blocks available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search blocks...", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    // MARK: - Block Grid

    private var blockGridView: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(filteredBlocks, id: \.rawValue) { blockType in
                    BlockLibraryItem(blockType: blockType, blockManager: blockManager)
                }
            }
            .padding()
        }
    }

    // MARK: - Template Section

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            HStack {
                Text("Templates")
                    .font(.headline)

                Spacer()

                Text("\(filteredTemplates.count) available")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    showingTemplateCreation = true
                } label: {
                    Label("Create Template", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .help("Capture the current configuration as a reusable template")
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(filteredTemplates, id: \.id) { template in
                        TemplatePreviewCard(template: template) {
                            selectedTemplate = template
                            showingTemplateDetail = true
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Computed Properties

    private var filteredBlocks: [BlockType] {
        let categoryBlocks = selectedCategory == .all ?
            BlockType.allCases :
            filteredBlocks(for: selectedCategory)

        if searchText.isEmpty {
            return categoryBlocks
        }

        return categoryBlocks.filter { blockType in
            blockType.displayName.localizedCaseInsensitiveContains(searchText) ||
            blockType.blockDescription.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func filteredBlocks(for category: LibraryCategory) -> [BlockType] {
        if category == .all {
            return BlockType.allCases
        }
        return BlockType.allCases.filter { $0.libraryCategory == category }
    }

    private var filteredTemplates: [BlockTemplate] {
        templates.filter { template in
            if selectedCategory != .all {
                return template.blockTypes.contains { $0.libraryCategory == selectedCategory }
            }

            if !searchText.isEmpty {
                return template.name.localizedCaseInsensitiveContains(searchText) ||
                       template.description.localizedCaseInsensitiveContains(searchText)
            }

            return true
        }
    }

    private func reloadTemplates() {
        let currentSelection = selectedTemplate?.id
        templates = BlockTemplate.loadAll()
        if let selection = currentSelection {
            selectedTemplate = templates.first(where: { $0.id == selection })
        }
    }

    private func deleteTemplate(_ template: BlockTemplate) {
        guard !template.isBuiltIn else { return }
        do {
            try BlockTemplate.delete(template)
            reloadTemplates()
            selectedTemplate = nil
            showingTemplateDetail = false
        } catch {
            templateError = "Failed to delete template: \(error.localizedDescription)"
        }
    }

    private func createTemplate(name: String, description: String) async -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return "Template name cannot be empty."
        }

        if templates.contains(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            return "A template named ‘\(trimmedName)’ already exists."
        }

        let configuration = await blockManager.getCurrentConfiguration()
        guard !configuration.blocks.isEmpty else {
            return "Create a template by selecting blocks in the editor first."
        }

        let now = Date()
        let templateConfig = BlockConfiguration(
            id: UUID(),
            name: trimmedName,
            createdDate: now,
            modifiedDate: now,
            blocks: configuration.blocks,
            connections: configuration.connections,
            version: configuration.version,
            metadata: configuration.metadata
        )

        let descriptionText = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var template = BlockTemplate(
            name: trimmedName,
            description: descriptionText.isEmpty ? trimmedName : descriptionText,
            createdDate: now,
            configuration: templateConfig,
            isBuiltIn: false
        )

        do {
            try template.persist()
            await MainActor.run {
                templates = BlockTemplate.loadAll()
                selectedTemplate = templates.first(where: { $0.id == template.id })
            }
            return nil
        } catch {
            return "Failed to save template: \(error.localizedDescription)"
        }
    }
}

struct TemplateCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    let existingNames: [String]
    let onCreate: (String, String) async -> String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Template Details") {
                    TextField("Name", text: $name)
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .disabled(isSaving)
            .navigationTitle("New Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: saveTemplate) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 220)
    }

    private func saveTemplate() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name cannot be empty."
            return
        }

        if existingNames.contains(where: { $0.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            errorMessage = "A template named ‘\(trimmedName)’ already exists."
            return
        }

        errorMessage = nil
        isSaving = true

        Task {
            let result = await onCreate(trimmedName, description)
            await MainActor.run {
                isSaving = false
                if let message = result {
                    errorMessage = message
                } else {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Block Library Item

struct BlockLibraryItem: View {
    let blockType: BlockType
    @ObservedObject var blockManager: BlockManagerServiceImpl

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            // Block icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(blockType.category.color.opacity(0.1))
                    .frame(height: 60)

                Image(systemName: blockType.icon)
                    .font(.title)
                    .foregroundColor(blockType.category.color)
            }

            // Block info
            VStack(spacing: 4) {
                Text(blockType.displayName)
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(blockType.blockDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            // Add button
            Button(action: addBlock) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add")
                }
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(blockType.category.color)
                .cornerRadius(6)
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0.8)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isHovered ? blockType.category.color : Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrag {
            NSItemProvider(object: blockType.rawValue as NSString)
        }
        .help(blockType.description)
    }

    private func addBlock() {
        Task {
            do {
                let centerPosition = CGPoint(x: 400, y: 300) // Default center position
                let _ = try await blockManager.createBlock(type: blockType, at: centerPosition)
            } catch {
                print("Failed to create block: \(error)")
            }
        }
    }
}

// MARK: - Template Preview Card

struct TemplatePreviewCard: View {
    let template: BlockTemplate
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Template preview
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 120, height: 80)

                // Mini block representations
                HStack(spacing: 4) {
                    ForEach(Array(template.blockTypes.prefix(3)), id: \.rawValue) { blockType in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(blockType.category.color.opacity(0.7))
                            .frame(width: 16, height: 12)
                    }

                    if template.blockTypes.count > 3 {
                        Text("+\(template.blockTypes.count - 3)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Template info
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.caption.bold())
                    .lineLimit(1)

                Text(template.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Use button
            Button("Use Template") {
                onSelect()
            }
            .font(.caption)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(width: 120)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Template Detail View

struct TemplateDetailView: View {
    let template: BlockTemplate
    @ObservedObject var blockManager: BlockManagerServiceImpl
    let onDismiss: () -> Void
    let onDelete: ((BlockTemplate) -> Void)?

    @Environment(\.dismiss) private var dismissSheet

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.title2.bold())

                    Text(template.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Close") {
                    dismissSheet()
                    onDismiss()
                }
            }

            // Template preview
            templatePreview

            // Template info
            templateInfo

            Spacer()

            // Actions
            HStack {
                Button("Cancel") {
                    dismissSheet()
                }
                .buttonStyle(.bordered)

                if let onDelete {
                    Button("Delete", role: .destructive) {
                        onDelete(template)
                        dismissSheet()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Apply Template") {
                    applyTemplate()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }

    private var templatePreview: some View {
        // Template visualization would go here
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.1))
            .frame(height: 200)
            .overlay(
                Text("Template Preview\n\(template.blockTypes.count) blocks")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            )
    }

    private var templateInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Includes:")
                .font(.headline)

            ForEach(template.blockTypes, id: \.rawValue) { blockType in
                HStack {
                    Image(systemName: blockType.icon)
                        .foregroundColor(blockType.category.color)
                        .frame(width: 20)

                    Text(blockType.displayName)

                    Spacer()
                }
            }
        }
    }

    private func applyTemplate() {
        Task {
            do {
                try await instantiateTemplate()
                dismissSheet()
                onDismiss()
            } catch {
                print("Failed to apply template: \(error)")
            }
        }
    }

    private func instantiateTemplate() async throws {
        let configuration = template.configuration
        var idMap: [UUID: UUID] = [:]

        for block in configuration.blocks {
            let position = CGPoint(
                x: block.position.x + 40,
                y: block.position.y + 40
            )
            let newBlock = try await blockManager.createBlock(type: block.type, at: position)
            idMap[block.id] = newBlock.id

            for (parameterName, value) in block.parameters {
                try await blockManager.updateBlockParameter(
                    blockId: newBlock.id,
                    parameterName: parameterName,
                    value: value.value
                )
            }
        }

        for connection in configuration.connections {
            guard let sourceId = idMap[connection.sourceBlockId],
                  let destinationId = idMap[connection.destinationBlockId] else { continue }

            try await blockManager.createConnection(
                from: sourceId,
                sourcePort: connection.sourcePort,
                to: destinationId,
                destinationPort: connection.destinationPort
            )
        }
    }
}

// MARK: - Supporting Types

enum LibraryCategory: String, CaseIterable {
    case all
    case oscillators
    case modulation
    case processing
    case analysis
    case output
    case noise

    var displayName: String {
        switch self {
        case .all: return "All Blocks"
        case .oscillators: return "Oscillators"
        case .modulation: return "Modulation"
        case .processing: return "Processing"
        case .analysis: return "Analysis"
        case .output: return "Output"
        case .noise: return "Noise"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.3x3"
        case .oscillators: return "waveform"
        case .modulation: return "antenna.radiowaves.left.and.right"
        case .processing: return "gearshape"
        case .analysis: return "chart.bar"
        case .output: return "speaker.wave.2"
        case .noise: return "dot.radiowaves.left.and.right"
        }
    }

    var color: Color {
        switch self {
        case .all: return .primary
        case .oscillators: return .blue
        case .modulation: return .purple
        case .processing: return .orange
        case .analysis: return .green
        case .output: return .pink
        case .noise: return .red
        }
    }
}

extension BlockType {
    var libraryCategory: LibraryCategory {
        switch self {
        case .sineOscillator, .squareOscillator, .triangleOscillator, .sawtoothOscillator, .linearChirp, .hyperbolicChirp:
            return .oscillators
        case .whiteNoise, .pinkNoise:
            return .noise
        case .amplitudeModulator, .frequencyModulator, .ringModulator:
            return .modulation
        case .lowPassFilter, .highPassFilter, .bandPassFilter, .mixer, .amplifier:
            return .processing
        case .spectrumAnalyzer, .levelMeter, .frequencyCounter:
            return .analysis
        case .audioOutput:
            return .output
        }
    }

    var icon: String {
        switch self {
        case .sineOscillator: return "waveform"
        case .squareOscillator: return "square"
        case .triangleOscillator: return "triangle"
        case .sawtoothOscillator: return "waveform"
        case .whiteNoise: return "dot.radiowaves.left.and.right"
        case .pinkNoise: return "dot.radiowaves.left.and.right"
        case .linearChirp: return "waveform"
        case .hyperbolicChirp: return "waveform"
        case .amplitudeModulator: return "waveform"
        case .frequencyModulator: return "antenna.radiowaves.left.and.right"
        case .ringModulator: return "circle"
        case .lowPassFilter: return "slider.horizontal.below.rectangle"
        case .highPassFilter: return "slider.horizontal.above.rectangle"
        case .bandPassFilter: return "slider.horizontal.3"
        case .mixer: return "slider.horizontal.below.rectangle"
        case .amplifier: return "speaker.wave.2"
        case .spectrumAnalyzer: return "chart.bar.fill"
        case .levelMeter: return "speedometer"
        case .frequencyCounter: return "stopwatch"
        case .audioOutput: return "speaker.wave.2.fill"
        }
    }

    var description: String {
        switch self {
        case .sineOscillator: return "Pure sine wave generator with precise frequency control"
        case .squareOscillator: return "Square wave generator with adjustable duty cycle"
        case .triangleOscillator: return "Triangle wave generator optimized for modulation"
        case .sawtoothOscillator: return "Sawtooth wave generator with smooth harmonics"
        case .whiteNoise: return "High-quality white noise generator"
        case .pinkNoise: return "Pink noise generator with 1/f frequency distribution"
        case .linearChirp: return "Linear frequency sweep generator"
        case .hyperbolicChirp: return "Hyperbolic chirp for cross-correlation measurements"
        case .amplitudeModulator: return "Amplitude modulation for tremolo effects"
        case .frequencyModulator: return "FM synthesis with configurable deviation"
        case .ringModulator: return "Ring modulation for bell-like tones"
        case .lowPassFilter: return "Filters out high frequencies above cutoff"
        case .highPassFilter: return "Filters out low frequencies below cutoff"
        case .bandPassFilter: return "Allows frequencies within specific band"
        case .mixer: return "Mix multiple signals with individual level control"
        case .amplifier: return "Adjust signal gain and output level"
        case .spectrumAnalyzer: return "Real-time FFT spectrum analysis"
        case .levelMeter: return "Monitor signal peak and RMS levels"
        case .frequencyCounter: return "Measure dominant frequency in input signal"
        case .audioOutput: return "Audio output with device routing"
        }
    }
}

struct BlockTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var description: String
    var createdDate: Date
    var configuration: BlockConfiguration
    var isBuiltIn: Bool
    var storageURL: URL?

    var blockTypes: [BlockType] {
        configuration.blocks.map { $0.type }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, createdDate, configuration, isBuiltIn
    }

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        createdDate: Date = Date(),
        configuration: BlockConfiguration,
        isBuiltIn: Bool = false,
        storageURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdDate = createdDate
        self.configuration = configuration
        self.isBuiltIn = isBuiltIn
        self.storageURL = storageURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        configuration = try container.decode(BlockConfiguration.self, forKey: .configuration)
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        storageURL = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encode(configuration, forKey: .configuration)
        try container.encode(isBuiltIn, forKey: .isBuiltIn)
    }

    mutating func persist() throws {
        let directory = try BlockTemplate.templatesDirectory()
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
        storageURL = url
    }

    static func loadAll() -> [BlockTemplate] {
        var templates = bundledTemplates()
        templates.append(contentsOf: loadUserTemplates())
        return templates.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func delete(_ template: BlockTemplate) throws {
        guard let url = template.storageURL else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func loadUserTemplates() -> [BlockTemplate] {
        guard let directory = try? templatesDirectory(createIfNeeded: false) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        } catch {
            return []
        }

        return files.compactMap { url in
            guard url.pathExtension.lowercased() == "json" else { return nil }
            do {
                var template = try decoder.decode(BlockTemplate.self, from: Data(contentsOf: url))
                template.storageURL = url
                template.isBuiltIn = false
                return template
            } catch {
                return nil
            }
        }
    }

    private static func templatesDirectory(createIfNeeded: Bool = true) throws -> URL {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = documentsDirectory.appendingPathComponent("Templates", isDirectory: true)

        if createIfNeeded && !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }

        return directory
    }

    private static func bundledTemplates() -> [BlockTemplate] {
        [
            makeBundledTemplate(
                name: "FM Synthesis",
                description: "Carrier and modulator routed through FM block",
                blockTypes: [.sineOscillator, .triangleOscillator, .frequencyModulator, .audioOutput],
                connections: [
                    (0, "signal", 2, "carrier"),
                    (1, "signal", 2, "modulation"),
                    (2, "output", 3, "input")
                ]
            ),
            makeBundledTemplate(
                name: "Noise Analysis",
                description: "White noise routed into analyzer and output",
                blockTypes: [.whiteNoise, .spectrumAnalyzer, .audioOutput],
                connections: [
                    (0, "signal", 1, "input"),
                    (0, "signal", 2, "input")
                ]
            ),
            makeBundledTemplate(
                name: "Basic Oscillator",
                description: "Simple sine oscillator feeding the output",
                blockTypes: [.sineOscillator, .audioOutput],
                connections: [
                    (0, "signal", 1, "input")
                ]
            )
        ]
    }

    private static func makeBundledTemplate(
        name: String,
        description: String,
        blockTypes: [BlockType],
        connections: [(sourceIndex: Int, sourcePort: String, destinationIndex: Int, destinationPort: String)] = []
    ) -> BlockTemplate {
        let now = Date()
        var blocks: [SignalBlock] = []

        for (index, type) in blockTypes.enumerated() {
            let position = CGPoint(
                x: 160.0 + CGFloat(index) * 180.0,
                y: 200.0
            )

            let block = SignalBlock(
                type: type,
                title: type.displayName,
                position: position,
                parameters: type.createDefaultParameters(),
                inputPorts: type.defaultInputPorts,
                outputPorts: type.defaultOutputPorts
            )
            blocks.append(block)
        }

        var connectionModels: [Connection] = []
        for link in connections {
            guard link.sourceIndex < blocks.count, link.destinationIndex < blocks.count else { continue }
            connectionModels.append(
                Connection(
                    sourceBlockId: blocks[link.sourceIndex].id,
                    sourcePort: link.sourcePort,
                    destinationBlockId: blocks[link.destinationIndex].id,
                    destinationPort: link.destinationPort,
                    signalType: .audio
                )
            )
        }

        let configuration = BlockConfiguration(
            id: UUID(),
            name: name,
            createdDate: now,
            modifiedDate: now,
            blocks: blocks,
            connections: connectionModels
        )

        return BlockTemplate(
            id: UUID(),
            name: name,
            description: description,
            createdDate: now,
            configuration: configuration,
            isBuiltIn: true
        )
    }
}

#Preview {
    BlockLibraryView(blockManager: BlockManagerServiceImpl(audioService: AudioBlockServiceImpl(avfAudioService: AVFAudioService())))
}
