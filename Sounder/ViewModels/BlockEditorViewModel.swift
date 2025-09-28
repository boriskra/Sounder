import SwiftUI
import Combine
import AVFoundation

/// Main view model coordinating all block editor services and managing application state
@MainActor
class BlockEditorViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isAudioPlaying: Bool = false
    @Published var currentConfiguration: BlockConfiguration?
    @Published var selectedBlock: SignalBlock?
    @Published var showingBlockLibrary: Bool = false
    @Published var showingParameterControls: Bool = true
    @Published var showingAudioDevices: Bool = false

    // Audio system state
    @Published var currentOutputDevice: OutputDevice?
    @Published var availableOutputDevices: [OutputDevice] = []
    @Published var audioEngineStatus: AudioEngineStatus = .stopped
    @Published var cpuUsage: Double = 0.0
    @Published var audioLatency: Double = 0.0

    // UI state
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showingError: Bool = false
    @Published var statusMessage: String?

    // Configuration management
    @Published var hasUnsavedChanges = false
    @Published var currentConfigurationURL: URL?
    @Published var recentConfigurations: [URL] = []

    // Performance monitoring
    @Published var performanceMetrics: PerformanceMetrics = PerformanceMetrics()
    @Published var showPerformanceMetrics = false
    @Published var enableAutoSave = true {
        didSet {
            guard autoSaveBindingReady else { return }
            configurationViewModel.setAutoSaveEnabled(enableAutoSave)
        }
    }

    // MARK: - Services

    let blockManager: BlockManagerService
    let audioBlockService: AudioBlockService
    let canvasService: BlockCanvasService

    // MARK: - Child ViewModels

    @Published var canvasViewModel: BlockCanvasViewModel
    let configurationViewModel: ConfigurationViewModel

    // MARK: - Private State

    private var cancellables: Set<AnyCancellable> = []
    private var performanceTimer: Timer?
    private var audioLevelTimer: Timer?
    private var autoSaveBindingReady: Bool = false

    // MARK: - Initialization

    init(
        blockManager: BlockManagerService,
        audioBlockService: AudioBlockService,
        canvasService: BlockCanvasService
    ) {
        self.blockManager = blockManager
        self.audioBlockService = audioBlockService
        self.canvasService = canvasService

        // Initialize child view models
        self.canvasViewModel = BlockCanvasViewModel(
            blockManager: blockManager,
            canvasService: canvasService
        )
        self.configurationViewModel = ConfigurationViewModel(
            blockManager: blockManager
        )

        setupBindings()
        setupPerformanceMonitoring()
        loadInitialState()

        autoSaveBindingReady = true
        configurationViewModel.setAutoSaveEnabled(enableAutoSave)
    }

    deinit {
        Task { @MainActor in
            stopPerformanceMonitoring()
        }
    }

    // MARK: - Setup

    private func setupBindings() {
        // Canvas selection changes
        canvasViewModel.$selectedBlocks
            .map { blocks in
                // Return the first selected block for parameter editing
                blocks.first
            }
            .sink { [weak self] selectedBlockId in
                Task { @MainActor in
                    await self?.updateSelectedBlock(selectedBlockId)
                }
            }
            .store(in: &cancellables)

        // Configuration changes
        configurationViewModel.$currentConfiguration
            .sink { [weak self] configuration in
                self?.currentConfiguration = configuration
            }
            .store(in: &cancellables)

        configurationViewModel.$hasUnsavedChanges
            .sink { [weak self] hasChanges in
                self?.hasUnsavedChanges = hasChanges
            }
            .store(in: &cancellables)

        configurationViewModel.$currentFileURL
            .sink { [weak self] url in
                self?.currentConfigurationURL = url
            }
            .store(in: &cancellables)

        // Audio service events
        NotificationCenter.default.publisher(for: .audioEngineStatusChanged)
            .sink { [weak self] notification in
                print("🔔 [DEBUG] BlockEditorViewModel - Received .audioEngineStatusChanged notification")
                if let status = notification.object as? AudioEngineStatus {
                    print("🔔 [DEBUG] BlockEditorViewModel - Status: \(status), displayName: \(status.displayName)")
                    self?.audioEngineStatus = status
                    self?.isAudioPlaying = (status == .running)
                    print("🔔 [DEBUG] BlockEditorViewModel - Updated audioEngineStatus: \(status), isAudioPlaying: \(status == .running)")
                } else {
                    print("🔔 [ERROR] BlockEditorViewModel - Invalid status object in notification: \(String(describing: notification.object))")
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .audioDeviceChanged)
            .sink { [weak self] notification in
                if let device = notification.object as? OutputDevice {
                    self?.currentOutputDevice = device
                }
            }
            .store(in: &cancellables)

        // Block manager events
        NotificationCenter.default.publisher(for: .blockCreated)
            .sink { [weak self] _ in
                self?.markConfigurationChanged()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .blockRemoved)
            .sink { [weak self] _ in
                self?.markConfigurationChanged()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .connectionCreated)
            .sink { [weak self] _ in
                self?.markConfigurationChanged()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .connectionRemoved)
            .sink { [weak self] _ in
                self?.markConfigurationChanged()
            }
            .store(in: &cancellables)
    }

    private func loadInitialState() {
        Task {
            await loadAvailableDevices()
            await loadRecentConfigurations()
        }
    }

    // MARK: - Audio Control

    func playAudio() async {
        print("🎵 [DEBUG] BlockEditorViewModel.playAudio() - Starting")
        isLoading = true
        statusMessage = "Starting audio processing..."

        do {
            print("🎵 [DEBUG] BlockEditorViewModel.playAudio() - Calling blockManager.startAudioProcessing()")
            // Add timeout to prevent indefinite hanging
            try await withTimeout(seconds: 10) { [self] in
                try await self.blockManager.startAudioProcessing()
            }

            print("🎵 [DEBUG] BlockEditorViewModel.playAudio() - Audio processing started successfully")
            isAudioPlaying = true
            statusMessage = "Audio playing"

            // Clear status message after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.statusMessage = nil
            }

        } catch {
            print("🎵 [ERROR] BlockEditorViewModel.playAudio() - Error: \(error)")
            isAudioPlaying = false
            statusMessage = nil
            await handleError(error, context: "starting audio")
        }

        isLoading = false
        print("🎵 [DEBUG] BlockEditorViewModel.playAudio() - Finished, isAudioPlaying: \(isAudioPlaying)")
    }

    // Helper function to add timeout to async operations
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            // Add the main operation
            group.addTask {
                try await operation()
            }

            // Add the timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AudioTimeoutError()
            }

            // Wait for the first task to complete (either operation or timeout)
            let result = try await group.next()
            group.cancelAll()

            guard let unwrappedResult = result else {
                throw AudioTimeoutError()
            }

            return unwrappedResult
        }
    }

    func stopAudio() async {
        isLoading = true
        statusMessage = "Stopping audio..."

        await blockManager.stopAudioProcessing()
        isAudioPlaying = false
        statusMessage = nil
        isLoading = false
    }

    func toggleAudio() async {
        if isAudioPlaying {
            await stopAudio()
        } else {
            await playAudio()
        }
    }

    // MARK: - Device Management

    private func loadAvailableDevices() async {
        let devices = await audioBlockService.getAvailableOutputDevices()
        availableOutputDevices = devices

        if let activeDevice = await audioBlockService.getCurrentOutputDevice() {
            currentOutputDevice = activeDevice
        } else if currentOutputDevice == nil {
            currentOutputDevice = devices.first
        }
    }

    func selectOutputDevice(_ device: OutputDevice) async {
        do {
            try await blockManager.setOutputDevice(device)
            currentOutputDevice = device
            statusMessage = "Switched to \(device.displayName)"

            // Clear status message after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.statusMessage = nil
            }

        } catch {
            await handleError(error, context: "switching audio device")
        }
    }

    func refreshAvailableDevices() async {
        await loadAvailableDevices()
    }

    // MARK: - Block Management

    func createBlock(type: BlockType, at position: CGPoint) async {
        do {
            let block: SignalBlock = try await blockManager.createBlock(type: type, at: position)
            canvasViewModel.selectBlock(block.id)
            markConfigurationChanged()

        } catch {
            await handleError(error, context: "creating block")
        }
    }

    func deleteSelectedBlocks() async {
        let selectedBlockIds: [UUID] = Array(canvasViewModel.selectedBlocks)

        for blockId in selectedBlockIds {
            do {
                try await blockManager.removeBlock(id: blockId)
            } catch {
                await handleError(error, context: "deleting block")
            }
        }

        canvasViewModel.clearSelection()
        markConfigurationChanged()
    }

    func updateBlockParameter(blockId: UUID, parameterName: String, value: Double) async {
        do {
            try await blockManager.updateBlockParameter(
                blockId: blockId,
                parameterName: parameterName,
                value: value
            )
            markConfigurationChanged()

        } catch {
            await handleError(error, context: "updating block parameter")
        }
    }

    private func updateSelectedBlock(_ blockId: UUID?) async {
        if let blockId = blockId {
            let configuration: BlockConfiguration = await blockManager.getCurrentConfiguration()
            selectedBlock = configuration.blocks.first { $0.id == blockId }

            // Auto-switch to parameters tab when a block is selected
            if selectedBlock != nil {
                showingParameterControls = true
                showingAudioDevices = false
            }
        } else {
            selectedBlock = nil
        }
    }

    // MARK: - Configuration Management

    func newConfiguration() async {
        if hasUnsavedChanges {
            // In a real app, show confirmation dialog
            // For now, proceed without saving
        }

        await blockManager.clearConfiguration()
        configurationViewModel.reset()
        canvasViewModel.clearSelection()
        canvasViewModel.resetCanvasView()

        statusMessage = "New configuration created"
        markConfigurationSaved()
    }

    func saveConfiguration() async {
        await configurationViewModel.saveConfiguration()
    }

    func saveConfigurationAs() async {
        await configurationViewModel.saveConfigurationAs()
    }

    func loadConfiguration() async {
        await configurationViewModel.loadConfiguration()
    }

    private func markConfigurationChanged() {
        hasUnsavedChanges = true
    }

    private func markConfigurationSaved() {
        hasUnsavedChanges = false
    }

    private func loadRecentConfigurations() async {
        // Load from UserDefaults or similar storage
        let defaults: UserDefaults = UserDefaults.standard
        if let urlStrings = defaults.array(forKey: "RecentConfigurations") as? [String] {
            recentConfigurations = urlStrings.compactMap { URL(string: $0) }
        }
    }

    private func addToRecentConfigurations(_ url: URL) {
        recentConfigurations.removeAll { $0 == url }
        recentConfigurations.insert(url, at: 0)

        // Keep only last 10
        if recentConfigurations.count > 10 {
            recentConfigurations = Array(recentConfigurations.prefix(10))
        }

        // Save to UserDefaults
        let urlStrings: [String] = recentConfigurations.map { $0.absoluteString }
        UserDefaults.standard.set(urlStrings, forKey: "RecentConfigurations")
    }

    // MARK: - UI State Management

    func showBlockLibrary() {
        showingBlockLibrary = true
    }

    func hideBlockLibrary() {
        showingBlockLibrary = false
    }

    func toggleParameterControls() {
        showingParameterControls.toggle()
    }

    func toggleAudioDevices() {
        showingAudioDevices.toggle()
    }

    // MARK: - Performance Monitoring

    private func setupPerformanceMonitoring() {
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updatePerformanceMetrics()
            }
        }

        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updateAudioLevels()
            }
        }
    }

    private func stopPerformanceMonitoring() {
        performanceTimer?.invalidate()
        audioLevelTimer?.invalidate()
        performanceTimer = nil
        audioLevelTimer = nil
    }

    private func updatePerformanceMetrics() async {
        // Get CPU usage
        cpuUsage = await getCPUUsage()

        // Get audio latency
        audioLatency = await getAudioLatency()

        // Update performance metrics
        performanceMetrics.update(
            cpuUsage: cpuUsage,
            audioLatency: audioLatency,
            isAudioPlaying: isAudioPlaying
        )
    }

    private func updateAudioLevels() async {
        // Update real-time audio level monitoring
        // This would integrate with the audio service for level metering
    }

    private func getCPUUsage() async -> Double {
        await audioBlockService.getAudioCPUUsage()
    }

    private func getAudioLatency() async -> Double {
        await audioBlockService.getAudioLatency()
    }

    // MARK: - Error Handling

    private func handleError(_ error: Error, context: String) async {
        let errorMessage: String = "Error \(context): \(error.localizedDescription)"
        print(errorMessage)

        self.errorMessage = errorMessage
        showingError = true

        // Auto-hide error after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.showingError = false
            self.errorMessage = nil
        }
    }

    func dismissError() {
        showingError = false
        errorMessage = nil
    }

    // MARK: - Keyboard Shortcuts

    func handleKeyCommand(_ command: KeyCommand) async {
        switch command {
        case .newConfiguration:
            await newConfiguration()
        case .saveConfiguration:
            await saveConfiguration()
        case .loadConfiguration:
            await loadConfiguration()
        case .playPause:
            await toggleAudio()
        case .deleteSelected:
            await deleteSelectedBlocks()
        case .selectAll:
            canvasViewModel.selectAll()
        case .deselectAll:
            canvasViewModel.clearSelection()
        case .showBlockLibrary:
            showBlockLibrary()
        }
    }
}

// MARK: - Supporting Types

enum AudioEngineStatus: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case error(String)

    var displayName: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting..."
        case .running: return "Running"
        case .stopping: return "Stopping..."
        case .error(let message): return "Error: \(message)"
        }
    }
}

struct PerformanceMetrics {
    var cpuUsage: Double = 0.0
    var memoryUsage: Double = 0.0
    var audioLatency: Double = 0.0
    var bufferUnderruns: Int = 0
    var lastUpdate: Date = Date()

    mutating func update(cpuUsage: Double, audioLatency: Double, isAudioPlaying: Bool) {
        self.cpuUsage = cpuUsage
        self.audioLatency = audioLatency
        self.lastUpdate = Date()

        // Update memory usage (simplified)
        self.memoryUsage = Double.random(in: 10...50) // MB
    }

    var isPerformanceGood: Bool {
        cpuUsage < 50 && audioLatency < 20 && bufferUnderruns == 0
    }
}

enum KeyCommand: String, CaseIterable {
    case newConfiguration = "cmd+n"
    case saveConfiguration = "cmd+s"
    case loadConfiguration = "cmd+o"
    case playPause = "space"
    case deleteSelected = "delete"
    case selectAll = "cmd+a"
    case deselectAll = "cmd+d"
    case showBlockLibrary = "cmd+l"

    var keyEquivalent: String {
        switch self {
        case .newConfiguration: return "n"
        case .saveConfiguration: return "s"
        case .loadConfiguration: return "o"
        case .playPause: return " "
        case .deleteSelected: return "\u{7f}" // Delete key
        case .selectAll: return "a"
        case .deselectAll: return "d"
        case .showBlockLibrary: return "l"
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .newConfiguration, .saveConfiguration, .loadConfiguration, .selectAll, .deselectAll, .showBlockLibrary:
            return .command
        case .playPause, .deleteSelected:
            return []
        }
    }
}

// MARK: - Error Types

struct AudioTimeoutError: Error, LocalizedError {
    var errorDescription: String? {
        return "Audio processing operation timed out"
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let audioEngineStatusChanged: Notification.Name = Notification.Name("audioEngineStatusChanged")
    static let audioDeviceChanged: Notification.Name = Notification.Name("audioDeviceChanged")
    static let performanceUpdate: Notification.Name = Notification.Name("performanceUpdate")
}
