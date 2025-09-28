import SwiftUI

/// Main block editor view integrating canvas, parameter controls, and device management
struct BlockEditorView: View {
    @StateObject var audioBlockService: AudioBlockServiceImpl
    @StateObject var blockManager: BlockManagerServiceImpl
    @StateObject var canvasService: BlockCanvasServiceImpl
    @StateObject var viewModel: BlockEditorViewModel

    @State var showingSettings = false
    @State var showingAbout = false

    init() {
        let avFoundationService = AVFAudioService()
        let audioService = AudioBlockServiceImpl(avfAudioService: avFoundationService)
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
