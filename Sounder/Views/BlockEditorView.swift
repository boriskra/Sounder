import SwiftUI

/// Main block editor view integrating canvas, parameter controls, and device management
struct BlockEditorView: View {
    @StateObject private var audioBlockService: AudioBlockServiceImpl
    @StateObject private var blockManager: BlockManagerServiceImpl
    @StateObject private var canvasService: BlockCanvasServiceImpl
    @StateObject private var viewModel: BlockEditorViewModel

    @State private var showingSettings = false
    @State private var showingAbout = false

    init() {
        let audioService = AudioBlockServiceImpl()
        let blockManagerService = BlockManagerServiceImpl(audioService: audioService)
        let canvasServiceImpl = BlockCanvasServiceImpl(blockManagerService: blockManagerService)
        let editorViewModel = BlockEditorViewModel(
            blockManager: blockManagerService,
            audioBlockService: audioService,
            canvasService: canvasServiceImpl
        )

        self._audioBlockService = StateObject(wrappedValue: audioService)
        self._blockManager = StateObject(wrappedValue: blockManagerService)
        self._canvasService = StateObject(wrappedValue: canvasServiceImpl)
        self._viewModel = StateObject(wrappedValue: editorViewModel)
    }

    var body: some View {
        HSplitView {
            // Main canvas area
            mainCanvasArea
                .frame(minWidth: 600)

            // Right sidebar
            rightSidebar
                .frame(width: 320)
        }
        .toolbar {
            toolbarContent
        }
        .overlay(alignment: .bottomLeading) {
            statusBar
        }
        .overlay(alignment: .topTrailing) {
            performanceOverlay
        }
        .sheet(isPresented: $viewModel.showingBlockLibrary) {
            BlockLibraryView(blockManager: blockManager)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK") {
                viewModel.dismissError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
        .onAppear {
            setupKeyboardShortcuts()
        }
        .environmentObject(blockManager)
        .environmentObject(canvasService)
    }

    // MARK: - Main Canvas Area

    private var mainCanvasArea: some View {
        VStack(spacing: 0) {
            // Canvas toolbar
            canvasToolbar

            // Main canvas
            ZStack {
                BlockCanvasView()

                // Block library overlay
                if viewModel.showingBlockLibrary {
                    BlockLibraryOverlay(viewModel: viewModel)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var canvasToolbar: some View {
        HStack {
            // Canvas tools
            ToolBarSection(title: "Tools") {
                ForEach(CanvasTool.allCases, id: \.self) { tool in
                    Button(action: {
                        viewModel.canvasViewModel.setTool(tool)
                    }) {
                        Image(systemName: tool.icon)
                    }
                    .help(tool.displayName)
                    .buttonStyle(.borderless)
                    .background(
                        viewModel.canvasViewModel.currentTool == tool ?
                        Color.accentColor.opacity(0.2) : Color.clear
                    )
                    .cornerRadius(4)
                }
            }

            Divider()

            // Canvas navigation
            ToolBarSection(title: "View") {
                Button(action: { viewModel.canvasViewModel.resetCanvasView() }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("Reset View")

                Button(action: { viewModel.canvasViewModel.fitToContent() }) {
                    Image(systemName: "rectangle.compress.vertical")
                }
                .help("Fit to Content")

                Button(action: { viewModel.canvasViewModel.toggleGrid() }) {
                    Image(systemName: "grid")
                }
                .help("Toggle Grid")
                .background(
                    viewModel.canvasViewModel.showingGrid ?
                    Color.accentColor.opacity(0.2) : Color.clear
                )
                .cornerRadius(4)
            }

            Spacer()

            // Audio controls
            audioControls
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.3)),
            alignment: .bottom
        )
    }

    private var audioControls: some View {
        HStack(spacing: 12) {
            // Play/Stop button
            Button(action: {
                Task {
                    await viewModel.toggleAudio()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isAudioPlaying ? "stop.fill" : "play.fill")
                    Text(viewModel.isAudioPlaying ? "Stop" : "Play")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(viewModel.isAudioPlaying ? Color.red : Color.green)
                .cornerRadius(8)
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isLoading)

            // Audio status
            VStack(alignment: .trailing, spacing: 2) {
                Text(viewModel.audioEngineStatus.displayName)
                    .font(.caption.bold())
                    .foregroundColor(audioStatusColor)

                if let device = viewModel.currentOutputDevice {
                    Text(device.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var audioStatusColor: Color {
        switch viewModel.audioEngineStatus {
        case .running: return .green
        case .stopped: return .secondary
        case .starting, .stopping: return .orange
        case .error: return .red
        }
    }

    // MARK: - Right Sidebar

    private var rightSidebar: some View {
        VStack(spacing: 0) {
            // Sidebar tabs
            sidebarTabs

            // Sidebar content
            TabView(selection: $viewModel.selectedSidebarTab) {
                // Parameter controls
                Group {
                    if viewModel.showingParameterControls {
                        ParameterControlsView(blockManager: blockManager)
                            .onReceive(viewModel.canvasViewModel.$selectedBlocks) { selectedBlocks in
                                if let firstSelected = selectedBlocks.first {
                                    Task {
                                        let configuration = await viewModel.blockManager.getCurrentConfiguration()
                                        if let block = configuration.blocks.first(where: { $0.id == firstSelected }) {
                                            if let parameterView = viewModel.parameterControlsView {
                                                parameterView.selectBlock(block)
                                            }
                                        }
                                    }
                                }
                            }
                    } else {
                        noParametersView
                    }
                }
                .tabItem {
                    Image(systemName: "slider.horizontal.3")
                    Text("Parameters")
                }
                .tag(SidebarTab.parameters)

                // Audio devices
                AudioDeviceView(blockManager: blockManager)
                    .tabItem {
                        Image(systemName: "speaker.wave.2")
                        Text("Devices")
                    }
                    .tag(SidebarTab.devices)

                // Configuration
                ConfigurationPanel(viewModel: viewModel)
                    .tabItem {
                        Image(systemName: "doc.text")
                        Text("Config")
                    }
                    .tag(SidebarTab.configuration)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var sidebarTabs: some View {
        HStack {
            Button(action: { viewModel.selectedSidebarTab = .parameters }) {
                VStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Parameters")
                        .font(.caption)
                }
            }
            .buttonStyle(.borderless)
            .foregroundColor(viewModel.selectedSidebarTab == .parameters ? .accentColor : .secondary)

            Button(action: { viewModel.selectedSidebarTab = .devices }) {
                VStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2")
                    Text("Devices")
                        .font(.caption)
                }
            }
            .buttonStyle(.borderless)
            .foregroundColor(viewModel.selectedSidebarTab == .devices ? .accentColor : .secondary)

            Button(action: { viewModel.selectedSidebarTab = .configuration }) {
                VStack(spacing: 4) {
                    Image(systemName: "doc.text")
                    Text("Config")
                        .font(.caption)
                }
            }
            .buttonStyle(.borderless)
            .foregroundColor(viewModel.selectedSidebarTab == .configuration ? .accentColor : .secondary)
        }
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.3)),
            alignment: .bottom
        )
    }

    private var noParametersView: some View {
        VStack(spacing: 16) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Block Selected")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Select a block on the canvas to adjust its parameters")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                    .cornerRadius(6)
            }

            Spacer()

            // Canvas info
            Text("Blocks: \(viewModel.currentConfiguration?.blocks.count ?? 0)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .cornerRadius(6)
        }
        .padding()
    }

    // MARK: - Performance Overlay

    private var performanceOverlay: some View {
        Group {
            if viewModel.showPerformanceMetrics {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("CPU: \(Int(viewModel.cpuUsage))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(viewModel.cpuUsage > 50 ? .red : .secondary)

                    Text("Latency: \(String(format: "%.1f", viewModel.audioLatency))ms")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(viewModel.audioLatency > 20 ? .orange : .secondary)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
                .cornerRadius(6)
                .padding()
            }
        }
    }

    // MARK: - Toolbar Content

    private var toolbarContent: some ToolbarContent {
        Group {
            // File operations
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {
                    Task {
                        await viewModel.newConfiguration()
                    }
                }) {
                    Image(systemName: "doc.badge.plus")
                }
                .help("New Configuration (⌘N)")

                Button(action: {
                    Task {
                        await viewModel.saveConfiguration()
                    }
                }) {
                    Image(systemName: "doc.badge.arrow.up")
                }
                .help("Save Configuration (⌘S)")
                .disabled(!viewModel.hasUnsavedChanges)

                Button(action: {
                    Task {
                        await viewModel.loadConfiguration()
                    }
                }) {
                    Image(systemName: "folder")
                }
                .help("Load Configuration (⌘O)")
            }

            // Block library
            ToolbarItem(placement: .primaryAction) {
                Button(action: { viewModel.showBlockLibrary() }) {
                    Image(systemName: "plus.square.on.square")
                }
                .help("Block Library (⌘L)")
            }

            // Settings
            ToolbarItem(placement: .automatic) {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
    }

    // MARK: - Helper Methods

    private func setupKeyboardShortcuts() {
        // Keyboard shortcuts are handled in the BlockEditorViewModel
        // This would be where we set up additional shortcuts if needed
    }
}

// MARK: - Supporting Views

struct ToolBarSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                content
            }
        }
    }
}

struct BlockLibraryOverlay: View {
    let viewModel: BlockEditorViewModel

    var body: some View {
        Color.black.opacity(0.3)
            .onTapGesture {
                viewModel.hideBlockLibrary()
            }
    }
}

struct ConfigurationPanel: View {
    @ObservedObject var viewModel: BlockEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Current configuration info
            configurationInfo

            Divider()

            // Recent files
            recentFilesSection

            Divider()

            // Templates
            templatesSection

            Spacer()
        }
        .padding()
    }

    private var configurationInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Configuration")
                .font(.headline)

            if let url = viewModel.currentConfigurationURL {
                Text(url.lastPathComponent)
                    .font(.subheadline.bold())

                Text(url.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else {
                Text("Untitled Configuration")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if viewModel.hasUnsavedChanges {
                Text("Unsaved changes")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private var recentFilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Files")
                .font(.headline)

            if viewModel.recentConfigurations.isEmpty {
                Text("No recent files")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(viewModel.recentConfigurations.prefix(5)), id: \.absoluteString) { url in
                    Button(action: {
                        Task {
                            await viewModel.configurationViewModel.loadConfiguration(from: url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.accentColor)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.deletingPathExtension().lastPathComponent)
                                    .font(.caption.bold())
                                    .lineLimit(1)

                                Text(url.path)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Templates")
                .font(.headline)

            ForEach(viewModel.configurationViewModel.getAvailableTemplates(), id: \.id) { template in
                Button(action: {
                    Task {
                        await viewModel.configurationViewModel.createFromTemplate(template)
                    }
                }) {
                    HStack {
                        Image(systemName: "doc.plaintext")
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .font(.caption.bold())

                            Text(template.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: BlockEditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Block Editor Settings")
                .font(.title2.bold())

            Form {
                Section("Performance") {
                    Toggle("Show Performance Metrics", isOn: $viewModel.showPerformanceMetrics)
                    Toggle("Enable Auto-save", isOn: $viewModel.enableAutoSave)
                }

                Section("Canvas") {
                    Toggle("Show Grid by Default", isOn: $viewModel.canvasViewModel.showingGrid)
                    Toggle("Snap to Grid", isOn: $viewModel.canvasViewModel.snapToGrid)
                }

                Section("Audio") {
                    HStack {
                        Text("Buffer Size:")
                        Spacer()
                        Text("512 samples") // This would be configurable
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Sounder Block Editor")
                .font(.title.bold())

            Text("Version 1.0")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Block-based audio signal generator for macOS")
                .font(.body)
                .multilineTextAlignment(.center)

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 300, height: 250)
    }
}

// MARK: - Supporting Types

enum SidebarTab: String, CaseIterable {
    case parameters
    case devices
    case configuration

    var displayName: String {
        switch self {
        case .parameters: return "Parameters"
        case .devices: return "Devices"
        case .configuration: return "Configuration"
        }
    }
}

// MARK: - Extensions

extension BlockEditorViewModel {
    var selectedSidebarTab: SidebarTab {
        get {
            if showingParameterControls { return .parameters }
            if showingAudioDevices { return .devices }
            return .configuration
        }
        set {
            showingParameterControls = (newValue == .parameters)
            showingAudioDevices = (newValue == .devices)
        }
    }

    var showPerformanceMetrics: Bool {
        get { performanceMetrics.isPerformanceGood }
        set { /* This would be stored in settings */ }
    }

    var enableAutoSave: Bool {
        get { true } // This would be stored in settings
        set { /* This would be stored in settings */ }
    }

    var parameterControlsView: ParameterControlsView? {
        // This would return a reference to the parameter controls view
        return nil
    }
}
