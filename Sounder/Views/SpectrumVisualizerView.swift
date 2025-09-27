import SwiftUI

struct SpectrumVisualizerView: View {
    var spectrum: [Float]

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<spectrum.count, id: \.self) { index in
                Rectangle()
                    .fill(Color.green)
                    .frame(width: 2, height: CGFloat(spectrum[index]) * 100)
            }
        }
    }
}
