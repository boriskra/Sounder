import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Sounder Block Editor")
                .font(.title.bold())

            Text("Version 1.0")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Block-based audio signal generator for macOS")
                .font(.body)
                .multilineTextAlignment(.center)

            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 300, height: 250)
    }
}
