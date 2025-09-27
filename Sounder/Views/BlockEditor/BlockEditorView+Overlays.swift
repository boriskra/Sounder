import SwiftUI

extension BlockEditorView {
    var statusBar: some View {
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

    var performanceOverlay: some View {
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
}
