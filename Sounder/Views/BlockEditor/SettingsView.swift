import SwiftUI

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
                        Text("512 samples")
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
    }
}
