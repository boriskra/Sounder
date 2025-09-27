import SwiftUI

extension BlockEditorView {
    var rightSidebar: some View {
        VStack(spacing: 0) {
            sidebarTabs

            TabView(selection: $viewModel.selectedSidebarTab) {
                Group {
                    if viewModel.showingParameterControls {
                        ParameterControlsView(blockManager: blockManager)
                            .onReceive(viewModel.canvasViewModel.$selectedBlocks) { selectedBlocks in
                                guard let firstSelected = selectedBlocks.first else { return }
                                Task {
                                    let configuration = await viewModel.blockManager.getCurrentConfiguration()
                                    if let block = configuration.blocks.first(where: { $0.id == firstSelected }) {
                                        viewModel.parameterControlsView?.selectBlock(block)
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

                AudioDeviceView(blockManager: blockManager)
                    .tabItem {
                        Image(systemName: "speaker.wave.2")
                        Text("Devices")
                    }
                    .tag(SidebarTab.devices)

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

    var sidebarTabs: some View {
        HStack {
            SidebarTabButton(
                icon: "slider.horizontal.3",
                label: "Parameters",
                isSelected: viewModel.selectedSidebarTab == .parameters
            ) {
                viewModel.selectedSidebarTab = .parameters
            }

            SidebarTabButton(
                icon: "speaker.wave.2",
                label: "Devices",
                isSelected: viewModel.selectedSidebarTab == .devices
            ) {
                viewModel.selectedSidebarTab = .devices
            }

            SidebarTabButton(
                icon: "doc.text",
                label: "Config",
                isSelected: viewModel.selectedSidebarTab == .configuration
            ) {
                viewModel.selectedSidebarTab = .configuration
            }
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

    var noParametersView: some View {
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
}

private struct SidebarTabButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
                    .font(.caption)
            }
        }
        .buttonStyle(.borderless)
        .foregroundColor(isSelected ? .accentColor : .secondary)
    }
}

enum SidebarTab: String, CaseIterable {
    case parameters
    case devices
    case configuration

    var displayName: String {
        switch self {
        case .parameters:
            return "Parameters"
        case .devices:
            return "Devices"
        case .configuration:
            return "Configuration"
        }
    }
}

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

    var parameterControlsView: ParameterControlsView? {
        nil
    }
}
