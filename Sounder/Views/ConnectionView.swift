import SwiftUI

/// Connection view for visualizing signal flow between audio blocks
/// Supports animated signal flow visualization and interactive connection management
struct ConnectionView: View {
    let connection: BlockConnection
    let blocks: [SignalBlock]
    @ObservedObject var canvasService: BlockCanvasServiceImpl
    @ObservedObject var blockManager: BlockManagerServiceImpl

    @State internal var signalFlow: Double = 0.0
    @State internal var connectionStrength: Double = 0.5
    @State internal var isHovered: Bool = false
    @State private var showingLabel: Bool = false

    // Animation state
    @State internal var flowAnimation: Bool = false
    internal let flowSpeed: Double = 2.0

    var body: some View {
        GeometryReader { _ in
            if let outputBlock = outputBlock,
               let inputBlock = inputBlock {
                let startPoint: CGPoint = calculatePortPosition(
                    block: outputBlock,
                    portName: connection.outputPort,
                    isOutput: true
                )
                let endPoint: CGPoint = calculatePortPosition(
                    block: inputBlock,
                    portName: connection.inputPort,
                    isOutput: false
                )

                ZStack {
                    // Main connection path
                    connectionPath(from: startPoint, to: endPoint)

                    // Signal flow animation
                    signalFlowIndicator(from: startPoint, to: endPoint)

                    // Connection label
                    if showingLabel {
                        connectionLabel(midpoint: calculateMidpoint(from: startPoint, to: endPoint))
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovered = hovering
                        showingLabel = hovering
                    }
                }
                .onTapGesture(count: 2) {
                    deleteConnection()
                }
                .contextMenu {
                    connectionContextMenu
                }
                .onAppear {
                    startSignalFlowAnimation()
                }
            }
        }
    }
}
