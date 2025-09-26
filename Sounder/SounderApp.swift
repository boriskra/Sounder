import SwiftUI

@main
struct SounderApp: App {
    private let audioService: any AudioService

    init() {
        if ProcessInfo.processInfo.arguments.contains("-ui_testing") {
            self.audioService = MockAudioService()
        } else {
            self.audioService = AVFAudioService()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    // Handle app termination - save any unsaved work
                    handleAppTermination()
                }
        }
        .commands {
            // Replace default File menu with custom items
            CommandGroup(replacing: .newItem) {
                Button("New Configuration") {
                    handleNewConfiguration()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save Configuration") {
                    handleSaveConfiguration()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save Configuration As...") {
                    handleSaveConfigurationAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Export Configuration...") {
                    handleExportConfiguration()
                }
                .keyboardShortcut("e", modifiers: .command)
            }

            // Custom File menu items
            CommandGroup(after: .saveItem) {
                Divider()

                Button("Load Configuration...") {
                    handleLoadConfiguration()
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    Button("Recent File 1") { /* Handle recent file */ }
                    Button("Recent File 2") { /* Handle recent file */ }
                    Divider()
                    Button("Clear Recent Files") {
                        handleClearRecentFiles()
                    }
                }
            }

            // Edit menu for block editor
            CommandGroup(after: .undoRedo) {
                Divider()

                Button("Select All Blocks") {
                    handleSelectAllBlocks()
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Deselect All") {
                    handleDeselectAll()
                }
                .keyboardShortcut("d", modifiers: .command)

                Divider()

                Button("Duplicate Selected") {
                    handleDuplicateSelected()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Delete Selected") {
                    handleDeleteSelected()
                }
                .keyboardShortcut(.delete)
            }

            // Audio menu
            CommandMenu("Audio") {
                Button("Play/Pause") {
                    handlePlayPause()
                }
                .keyboardShortcut(.space)

                Button("Stop") {
                    handleStop()
                }
                .keyboardShortcut(.escape)

                Divider()

                Menu("Output Device") {
                    Button("Default Output") {
                        handleSelectOutputDevice("default")
                    }
                    Button("Bluetooth Device") {
                        handleSelectOutputDevice("bluetooth")
                    }
                    Divider()
                    Button("Refresh Devices") {
                        handleRefreshDevices()
                    }
                }

                Divider()

                Button("Audio Settings...") {
                    handleAudioSettings()
                }
                .keyboardShortcut(",", modifiers: [.command, .option])
            }

            // Block Editor menu
            CommandMenu("Blocks") {
                Button("Show Block Library") {
                    handleShowBlockLibrary()
                }
                .keyboardShortcut("l", modifiers: .command)

                Divider()

                Menu("Add Block") {
                    Button("Sine Oscillator") {
                        handleAddBlock(.sineOscillator)
                    }
                    .keyboardShortcut("1", modifiers: .command)

                    Button("Triangle Oscillator") {
                        handleAddBlock(.triangleOscillator)
                    }
                    .keyboardShortcut("2", modifiers: .command)

                    Button("Frequency Modulator") {
                        handleAddBlock(.frequencyModulator)
                    }
                    .keyboardShortcut("3", modifiers: .command)

                    Button("White Noise") {
                        handleAddBlock(.whiteNoise)
                    }
                    .keyboardShortcut("4", modifiers: .command)

                    Button("Spectrum Analyzer") {
                        handleAddBlock(.spectrumAnalyzer)
                    }
                    .keyboardShortcut("5", modifiers: .command)

                    Button("Audio Output") {
                        handleAddBlock(.audioOutput)
                    }
                    .keyboardShortcut("6", modifiers: .command)
                }

                Divider()

                Menu("Templates") {
                    Button("Basic Sine Wave") {
                        handleCreateTemplate("basic_sine")
                    }

                    Button("FM Synthesis") {
                        handleCreateTemplate("fm_synthesis")
                    }

                    Button("Noise Analysis") {
                        handleCreateTemplate("noise_analysis")
                    }
                }
            }

            // View menu
            CommandGroup(after: .toolbar) {
                Divider()

                Button("Reset Canvas View") {
                    handleResetCanvasView()
                }
                .keyboardShortcut("0", modifiers: .command)

                Button("Fit to Content") {
                    handleFitToContent()
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button("Toggle Grid") {
                    handleToggleGrid()
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Toggle Snap to Grid") {
                    handleToggleSnapToGrid()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Divider()

                Button("Show Parameters Panel") {
                    handleShowParametersPanel()
                }
                .keyboardShortcut("p", modifiers: .command)

                Button("Show Audio Devices Panel") {
                    handleShowAudioDevicesPanel()
                }
                .keyboardShortcut("m", modifiers: .command)
            }

            // Help menu additions
            CommandGroup(after: .help) {
                Divider()

                Button("Block Editor Help") {
                    handleBlockEditorHelp()
                }
                .keyboardShortcut("?", modifiers: .command)

                Button("Keyboard Shortcuts") {
                    handleShowKeyboardShortcuts()
                }

                Button("Audio Troubleshooting") {
                    handleAudioTroubleshooting()
                }
            }
        }

        // Settings window
        Settings {
            SettingsWindow()
        }
    }

    // MARK: - Menu Handlers

    private func handleAppTermination() {
        // Post notification for any view models to save state
        NotificationCenter.default.post(name: .appWillTerminate, object: nil)
    }

    // File operations
    private func handleNewConfiguration() {
        NotificationCenter.default.post(name: .newConfigurationRequested, object: nil)
    }

    private func handleSaveConfiguration() {
        NotificationCenter.default.post(name: .saveConfigurationRequested, object: nil)
    }

    private func handleSaveConfigurationAs() {
        NotificationCenter.default.post(name: .saveConfigurationAsRequested, object: nil)
    }

    private func handleLoadConfiguration() {
        NotificationCenter.default.post(name: .loadConfigurationRequested, object: nil)
    }

    private func handleExportConfiguration() {
        NotificationCenter.default.post(name: .exportConfigurationRequested, object: nil)
    }

    private func handleClearRecentFiles() {
        NotificationCenter.default.post(name: .clearRecentFilesRequested, object: nil)
    }

    // Edit operations
    private func handleSelectAllBlocks() {
        NotificationCenter.default.post(name: .selectAllBlocksRequested, object: nil)
    }

    private func handleDeselectAll() {
        NotificationCenter.default.post(name: .deselectAllRequested, object: nil)
    }

    private func handleDuplicateSelected() {
        NotificationCenter.default.post(name: .duplicateSelectedRequested, object: nil)
    }

    private func handleDeleteSelected() {
        NotificationCenter.default.post(name: .deleteSelectedRequested, object: nil)
    }

    // Audio operations
    private func handlePlayPause() {
        NotificationCenter.default.post(name: .playPauseRequested, object: nil)
    }

    private func handleStop() {
        NotificationCenter.default.post(name: .stopRequested, object: nil)
    }

    private func handleSelectOutputDevice(_ deviceId: String) {
        NotificationCenter.default.post(name: .selectOutputDeviceRequested, object: deviceId)
    }

    private func handleRefreshDevices() {
        NotificationCenter.default.post(name: .refreshDevicesRequested, object: nil)
    }

    private func handleAudioSettings() {
        NotificationCenter.default.post(name: .showAudioSettingsRequested, object: nil)
    }

    // Block operations
    private func handleShowBlockLibrary() {
        NotificationCenter.default.post(name: .showBlockLibraryRequested, object: nil)
    }

    private func handleAddBlock(_ blockType: BlockType) {
        NotificationCenter.default.post(name: .addBlockRequested, object: blockType)
    }

    private func handleCreateTemplate(_ templateId: String) {
        NotificationCenter.default.post(name: .createTemplateRequested, object: templateId)
    }

    // View operations
    private func handleResetCanvasView() {
        NotificationCenter.default.post(name: .resetCanvasViewRequested, object: nil)
    }

    private func handleFitToContent() {
        NotificationCenter.default.post(name: .fitToContentRequested, object: nil)
    }

    private func handleToggleGrid() {
        NotificationCenter.default.post(name: .toggleGridRequested, object: nil)
    }

    private func handleToggleSnapToGrid() {
        NotificationCenter.default.post(name: .toggleSnapToGridRequested, object: nil)
    }

    private func handleShowParametersPanel() {
        NotificationCenter.default.post(name: .showParametersPanelRequested, object: nil)
    }

    private func handleShowAudioDevicesPanel() {
        NotificationCenter.default.post(name: .showAudioDevicesPanelRequested, object: nil)
    }

    // Help operations
    private func handleBlockEditorHelp() {
        if let url = URL(string: "https://sounder.app/help/block-editor") {
            NSWorkspace.shared.open(url)
        }
    }

    private func handleShowKeyboardShortcuts() {
        NotificationCenter.default.post(name: .showKeyboardShortcutsRequested, object: nil)
    }

    private func handleAudioTroubleshooting() {
        if let url = URL(string: "https://sounder.app/help/audio-troubleshooting") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Settings Window

struct SettingsWindow: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("General")
                }

            AudioSettingsView()
                .tabItem {
                    Image(systemName: "speaker.wave.2")
                    Text("Audio")
                }

            BlockEditorSettingsView()
                .tabItem {
                    Image(systemName: "square.grid.3x3")
                    Text("Block Editor")
                }
        }
        .frame(width: 450, height: 350)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("enableAutoSave") private var enableAutoSave: Bool = true
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 30.0
    @AppStorage("showWelcomeScreen") private var showWelcomeScreen: Bool = true

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show welcome screen on startup", isOn: $showWelcomeScreen)
                Toggle("Enable auto-save", isOn: $enableAutoSave)

                if enableAutoSave {
                    HStack {
                        Text("Auto-save interval:")
                        Spacer()
                        Slider(value: $autoSaveInterval, in: 10...300, step: 10)
                        Text("\(Int(autoSaveInterval))s")
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding()
    }
}

struct AudioSettingsView: View {
    @AppStorage("bufferSize") private var bufferSize: Int = 512
    @AppStorage("sampleRate") private var sampleRate: Int = 48000
    @AppStorage("enableBluetoothOptimization") private var enableBluetoothOptimization: Bool = true

    var body: some View {
        Form {
            Section("Audio Engine") {
                HStack {
                    Text("Buffer size:")
                    Spacer()
                    Picker("Buffer Size", selection: $bufferSize) {
                        Text("256 samples").tag(256)
                        Text("512 samples").tag(512)
                        Text("1024 samples").tag(1024)
                        Text("2048 samples").tag(2048)
                    }
                }

                HStack {
                    Text("Sample rate:")
                    Spacer()
                    Picker("Sample Rate", selection: $sampleRate) {
                        Text("44.1 kHz").tag(44100)
                        Text("48 kHz").tag(48000)
                        Text("96 kHz").tag(96000)
                    }
                }
            }

            Section("Device Settings") {
                Toggle("Optimize for Bluetooth devices", isOn: $enableBluetoothOptimization)
            }
        }
        .padding()
    }
}

struct BlockEditorSettingsView: View {
    @AppStorage("showGrid") private var showGrid: Bool = true
    @AppStorage("snapToGrid") private var snapToGrid: Bool = true
    @AppStorage("gridSize") private var gridSize: Double = 20.0
    @AppStorage("showPerformanceMetrics") private var showPerformanceMetrics: Bool = false

    var body: some View {
        Form {
            Section("Canvas") {
                Toggle("Show grid", isOn: $showGrid)
                Toggle("Snap to grid", isOn: $snapToGrid)

                HStack {
                    Text("Grid size:")
                    Spacer()
                    Slider(value: $gridSize, in: 10...50, step: 5)
                    Text("\(Int(gridSize))px")
                        .monospacedDigit()
                }
            }

            Section("Performance") {
                Toggle("Show performance metrics", isOn: $showPerformanceMetrics)
            }
        }
        .padding()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    // App lifecycle
    static let appWillTerminate = Notification.Name("appWillTerminate")

    // File operations
    static let newConfigurationRequested = Notification.Name("newConfigurationRequested")
    static let saveConfigurationRequested = Notification.Name("saveConfigurationRequested")
    static let saveConfigurationAsRequested = Notification.Name("saveConfigurationAsRequested")
    static let loadConfigurationRequested = Notification.Name("loadConfigurationRequested")
    static let exportConfigurationRequested = Notification.Name("exportConfigurationRequested")
    static let clearRecentFilesRequested = Notification.Name("clearRecentFilesRequested")

    // Edit operations
    static let selectAllBlocksRequested = Notification.Name("selectAllBlocksRequested")
    static let deselectAllRequested = Notification.Name("deselectAllRequested")
    static let duplicateSelectedRequested = Notification.Name("duplicateSelectedRequested")
    static let deleteSelectedRequested = Notification.Name("deleteSelectedRequested")

    // Audio operations
    static let playPauseRequested = Notification.Name("playPauseRequested")
    static let stopRequested = Notification.Name("stopRequested")
    static let selectOutputDeviceRequested = Notification.Name("selectOutputDeviceRequested")
    static let refreshDevicesRequested = Notification.Name("refreshDevicesRequested")
    static let showAudioSettingsRequested = Notification.Name("showAudioSettingsRequested")

    // Block operations
    static let showBlockLibraryRequested = Notification.Name("showBlockLibraryRequested")
    static let addBlockRequested = Notification.Name("addBlockRequested")
    static let createTemplateRequested = Notification.Name("createTemplateRequested")

    // View operations
    static let resetCanvasViewRequested = Notification.Name("resetCanvasViewRequested")
    static let fitToContentRequested = Notification.Name("fitToContentRequested")
    static let toggleGridRequested = Notification.Name("toggleGridRequested")
    static let toggleSnapToGridRequested = Notification.Name("toggleSnapToGridRequested")
    static let showParametersPanelRequested = Notification.Name("showParametersPanelRequested")
    static let showAudioDevicesPanelRequested = Notification.Name("showAudioDevicesPanelRequested")

    // Help operations
    static let showKeyboardShortcutsRequested = Notification.Name("showKeyboardShortcutsRequested")
}
