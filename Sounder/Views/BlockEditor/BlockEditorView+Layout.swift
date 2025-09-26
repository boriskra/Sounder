import SwiftUI

private extension BlockEditorView {
    var mainCanvasArea: some View {
        VStack(spacing: 0) {
            canvasToolbar

            ZStack {
                BlockCanvasView()

                if viewModel.showingBlockLibrary {
                    BlockLibraryOverlay(viewModel: viewModel)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    var canvasToolbar: some View {
        HStack {
            ToolBarSection(title: "Tools") {
                ForEach(CanvasTool.allCases, id: \.self) { tool in
                    Button {
                        viewModel.canvasViewModel.setTool(tool)
                    } label: {
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

            ToolBarSection(title: "View") {
                Button {
                    viewModel.canvasViewModel.resetCanvasView()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("Reset View")

                Button {
                    viewModel.canvasViewModel.fitToContent()
                } label: {
                    Image(systemName: "rectangle.compress.vertical")
                }
                .help("Fit to Content")

                Button {
                    viewModel.canvasViewModel.toggleGrid()
                } label: {
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

    var audioControls: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await viewModel.toggleAudio()
                }
            } label: {
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

    var audioStatusColor: Color {
        switch viewModel.audioEngineStatus {
        case .running:
            return .green
        case .stopped:
            return .secondary
        case .starting, .stopping:
            return .orange
        case .error:
            return .red
        }
    }
}
