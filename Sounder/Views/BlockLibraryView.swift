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
                TemplateDetailView(template: template, blockManager: blockManager) {
                    dismiss()
                }
            }
        }
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
        BlockTemplate.allTemplates.filter { template in
            if selectedCategory != .all {
                return template.blocks.contains { $0.libraryCategory == selectedCategory }
            }

            if !searchText.isEmpty {
                return template.name.localizedCaseInsensitiveContains(searchText) ||
                       template.description.localizedCaseInsensitiveContains(searchText)
            }

            return true
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
                    ForEach(Array(template.blocks.prefix(3)), id: \.rawValue) { blockType in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(blockType.category.color.opacity(0.7))
                            .frame(width: 16, height: 12)
                    }

                    if template.blocks.count > 3 {
                        Text("+\(template.blocks.count - 3)")
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
                    onDismiss()
                }
                .buttonStyle(.bordered)

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
                Text("Template Preview\n\(template.blocks.count) blocks")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            )
    }

    private var templateInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Includes:")
                .font(.headline)

            ForEach(template.blocks, id: \.rawValue) { blockType in
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
            // Create all blocks from template
            do {
                for (index, blockType) in template.blocks.enumerated() {
                    let position = CGPoint(
                        x: 200 + (index * 150),
                        y: 200
                    )
                    let _ = try await blockManager.createBlock(type: blockType, at: position)
                }

                // Add connections if defined in template
                // This would require extending the template structure to include connections

                onDismiss()
            } catch {
                print("Failed to apply template: \(error)")
            }
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

struct BlockTemplate {
    let id = UUID()
    let name: String
    let description: String
    let blocks: [BlockType]

    static let allTemplates: [BlockTemplate] = [
        BlockTemplate(
            name: "FM Synthesis",
            description: "Classic frequency modulation setup with carrier and modulator",
            blocks: [.sineOscillator, .triangleOscillator, .frequencyModulator, .audioOutput]
        ),
        BlockTemplate(
            name: "Noise Analysis",
            description: "White noise generator with spectrum analyzer",
            blocks: [.whiteNoise, .spectrumAnalyzer, .audioOutput]
        ),
        BlockTemplate(
            name: "Basic Oscillator",
            description: "Simple sine wave with output",
            blocks: [.sineOscillator, .audioOutput]
        )
    ]
}

#Preview {
    BlockLibraryView(blockManager: BlockManagerServiceImpl(audioService: AudioBlockServiceImpl()))
}
