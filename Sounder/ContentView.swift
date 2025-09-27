import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @State private var selectedTab: AppTab = .spectrum



    var body: some View {
        NavigationSplitView {
            // Sidebar navigation
            List(AppTab.allCases, id: \.self, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    HStack {
                        Image(systemName: tab.icon)
                            .frame(width: 20)
                        Text(tab.displayName)
                    }
                }
            }
            .navigationTitle("Sounder")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            // Main content area
            Group {
                switch selectedTab {
                case .spectrum:
                    spectrumView
                case .blockEditor:
                    blockEditorView
                }
            }
            .navigationTitle(selectedTab.displayName)
        }
        .navigationSplitViewStyle(.prominentDetail)
    }

    // MARK: - Spectrum View (Original)

    private var spectrumView: some View {
        VStack {
            Text("Spectrum")
                .font(.title)
            SpectrumVisualizerView(spectrum: viewModel.spectrum)
                .frame(height: 100)
                .padding()

            Divider()

            HStack {
                VStack {
                    Text("Sounds")
                        .font(.headline)
                    SoundSelectionView(sounds: viewModel.sounds, selectedSound: $viewModel.selectedSound)
                }
                Divider()
                VStack {
                    Text("Output Devices")
                        .font(.headline)
                    DeviceSelectionView(devices: viewModel.devices, selectedDevice: $viewModel.selectedDevice)
                }
            }

            Divider()

            HStack {
                Button(action: {
                    viewModel.play()
                }) {
                    Text("Play")
                }
                Button(action: {
                    viewModel.stop()
                }) {
                    Text("Stop")
                }
            }
            .padding()

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Block Editor View (New)

    private var blockEditorView: some View {
        BlockEditorView()
    }
}

// MARK: - Supporting Types

enum AppTab: String, CaseIterable {
    case spectrum
    case blockEditor

    var displayName: String {
        switch self {
        case .spectrum: return "Spectrum Analyzer"
        case .blockEditor: return "Block Editor"
        }
    }

    var icon: String {
        switch self {
        case .spectrum: return "chart.bar.fill"
        case .blockEditor: return "square.grid.3x3.fill"
        }
    }
}
