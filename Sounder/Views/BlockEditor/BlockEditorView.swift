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
            mainCanvasArea
                .frame(minWidth: 600)

            rightSidebar
                .frame(width: 320)
        }
        .toolbar { toolbarContent }
        .overlay(alignment: .bottomLeading) { statusBar }
        .overlay(alignment: .topTrailing) { performanceOverlay }
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
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
        .onAppear { setupKeyboardShortcuts() }
        .environmentObject(blockManager)
        .environmentObject(canvasService)
    }

    private func setupKeyboardShortcuts() {
        // Keyboard shortcuts are handled in BlockEditorViewModel
    }
}
