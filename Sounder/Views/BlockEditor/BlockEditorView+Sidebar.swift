import SwiftUI

extension BlockEditorView {
    var rightSidebar: some View {
        VStack(spacing: 0) {
            TabView(selection: $viewModel.selectedSidebarTab) {
                Group {
                    if viewModel.showingParameterControls {
                        ParameterControlsView(
                            blockManager: blockManager,
                            selectedBlock: viewModel.selectedBlock
                        )
                    } else {
                        noParametersView
                    }
                }
                .tabItem {
                    Text("Parameters")
                }
                .tag(SidebarTab.parameters)

                AudioDeviceView(blockManager: blockManager)
                    .tabItem {
                        Text("Devices")
                    }
                    .tag(SidebarTab.devices)

                ConfigurationPanel(viewModel: viewModel)
                    .tabItem {
                        Text("Config")
                    }
                    .tag(SidebarTab.configuration)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
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

}
