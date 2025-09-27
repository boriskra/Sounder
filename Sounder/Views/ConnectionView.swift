import SwiftUI

/// Connection view for visualizing signal flow between audio blocks
/// Supports animated signal flow visualization and interactive connection management
struct ConnectionView: View {
    let connection: BlockConnection
    let blocks: [SignalBlock]
    @ObservedObject var canvasService: BlockCanvasServiceImpl
    @ObservedObject var blockManager: BlockManagerServiceImpl

    @State private var signalFlow: Double = 0.0
    @State private var connectionStrength: Double = 0.5
    @State private var isHovered = false
    @State private var showingLabel = false

    // Animation state
    @State private var flowAnimation: Bool = false
    private let flowSpeed: Double = 2.0

    var body: some View {
        GeometryReader { geometry in
            if let outputBlock = outputBlock,
               let inputBlock = inputBlock {

                let startPoint = calculatePortPosition(
                    block: outputBlock,
                    portName: connection.outputPort,
                    isOutput: true
                )
                let endPoint = calculatePortPosition(
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

    // MARK: - Block References

    private var outputBlock: SignalBlock? {
        blocks.first { $0.id == connection.outputBlockId }
    }

    private var inputBlock: SignalBlock? {
        blocks.first { $0.id == connection.inputBlockId }
    }

    // MARK: - Connection Path

    private func connectionPath(from startPoint: CGPoint, to endPoint: CGPoint) -> some View {
        Canvas { context, size in
            drawConnectionCurve(
                context: context,
                from: startPoint,
                to: endPoint,
                strength: connectionStrength,
                isHovered: isHovered
            )
        }
        .allowsHitTesting(true)
    }

    private func drawConnectionCurve(
        context: GraphicsContext,
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        strength: Double,
        isHovered: Bool
    ) {
        let path = createConnectionPath(from: startPoint, to: endPoint)

        // Connection shadow
        if isHovered {
            context.stroke(
                path,
                with: .color(.black.opacity(0.3)),
                style: StrokeStyle(lineWidth: 6, lineCap: .round)
            )
        }

        // Main connection line
        let lineWidth = isHovered ? 4.0 : 2.0
        let opacity = strength * (isHovered ? 1.0 : 0.8)

        context.stroke(
            path,
            with: .color(connectionColor.opacity(opacity)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )

        // Connection strength indicator (line thickness variation)
        if strength > 0.1 {
            let strengthPath = createConnectionPath(from: startPoint, to: endPoint)
            context.stroke(
                strengthPath,
                with: .color(connectionColor.opacity(0.3)),
                style: StrokeStyle(
                    lineWidth: lineWidth * strength,
                    lineCap: .round
                )
            )
        }
    }

    private func createConnectionPath(from startPoint: CGPoint, to endPoint: CGPoint) -> Path {
        Path { path in
            path.move(to: startPoint)

            // Calculate control points for smooth curve
            let controlPoint1 = CGPoint(
                x: startPoint.x + connectionCurvature,
                y: startPoint.y
            )
            let controlPoint2 = CGPoint(
                x: endPoint.x - connectionCurvature,
                y: endPoint.y
            )

            path.addCurve(
                to: endPoint,
                control1: controlPoint1,
                control2: controlPoint2
            )
        }
    }

    private var connectionCurvature: CGFloat {
        let distance = abs((outputBlock?.position.x ?? 0) - (inputBlock?.position.x ?? 0))
        return min(max(CGFloat(distance * 0.3), 30), 100)
    }

    private var connectionColor: Color {
        // Color based on signal type and strength
        let baseColor: Color = .blue
        let strengthFactor = connectionStrength

        if strengthFactor > 0.8 {
            return .green
        } else if strengthFactor > 0.5 {
            return baseColor
        } else if strengthFactor > 0.2 {
            return .orange
        } else {
            return .red
        }
    }

    // MARK: - Signal Flow Animation

    private func signalFlowIndicator(from startPoint: CGPoint, to endPoint: CGPoint) -> some View {
        Canvas { context, size in
            if flowAnimation && connectionStrength > 0.1 {
                drawSignalFlowDots(
                    context: context,
                    from: startPoint,
                    to: endPoint
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func drawSignalFlowDots(
        context: GraphicsContext,
        from startPoint: CGPoint,
        to endPoint: CGPoint
    ) {
        let path = createConnectionPath(from: startPoint, to: endPoint)
        let pathLength = estimatePathLength(from: startPoint, to: endPoint)

        // Draw multiple flow dots
        for index in 0..<3 {
            let offset = Double(index) * 0.33
            let progress = fmod(signalFlow + offset, 1.0)

            if progress > 0 && progress < 1 {
                let point = interpolateAlongPath(
                    path: path,
                    progress: progress,
                    from: startPoint,
                    to: endPoint
                )

                let dotSize = 4.0 * connectionStrength
                let opacity = sin(progress * .pi) * connectionStrength

                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - dotSize / 2,
                        y: point.y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )),
                    with: .color(.white.opacity(opacity))
                )
            }
        }
    }

    private func interpolateAlongPath(
        path: Path,
        progress: Double,
        from startPoint: CGPoint,
        to endPoint: CGPoint
    ) -> CGPoint {
        // Simplified cubic bezier interpolation
        let interpolationProgress = progress
        let controlPoint1 = CGPoint(
            x: startPoint.x + connectionCurvature,
            y: startPoint.y
        )
        let controlPoint2 = CGPoint(
            x: endPoint.x - connectionCurvature,
            y: endPoint.y
        )

        let xPosition = pow(1 - interpolationProgress, 3) * startPoint.x +
                3 * pow(1 - interpolationProgress, 2) * interpolationProgress * controlPoint1.x +
                3 * (1 - interpolationProgress) * pow(interpolationProgress, 2) * controlPoint2.x +
                pow(interpolationProgress, 3) * endPoint.x

        let yPosition = pow(1 - interpolationProgress, 3) * startPoint.y +
                3 * pow(1 - interpolationProgress, 2) * interpolationProgress * controlPoint1.y +
                3 * (1 - interpolationProgress) * pow(interpolationProgress, 2) * controlPoint2.y +
                pow(interpolationProgress, 3) * endPoint.y

        return CGPoint(x: xPosition, y: yPosition)
    }

    private func estimatePathLength(from startPoint: CGPoint, to endPoint: CGPoint) -> Double {
        let xDifference = endPoint.x - startPoint.x
        let yDifference = endPoint.y - startPoint.y
        return sqrt(xDifference * xDifference + yDifference * yDifference) * 1.2 // Approximate curve length
    }

    // MARK: - Connection Label

    private func connectionLabel(midpoint: CGPoint) -> some View {
        VStack(spacing: 2) {
            Text("\(connection.outputPort) → \(connection.inputPort)")
                .font(.caption2.bold())
                .foregroundColor(.primary)

            Text("Strength: \(Int(connectionStrength * 100))%")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(connectionColor, lineWidth: 1)
                )
        )
        .position(midpoint)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Context Menu

    private var connectionContextMenu: some View {
        VStack {
            Text("Connection")
                .font(.headline)

            Divider()

            Text("From: \(outputBlock?.title ?? "Unknown") (\(connection.outputPort))")
                .font(.caption)

            Text("To: \(inputBlock?.title ?? "Unknown") (\(connection.inputPort))")
                .font(.caption)

            Divider()

            Button("Inspect Signal") {
                inspectConnection()
            }

            Button("Toggle Mute") {
                toggleConnectionMute()
            }

            Button("Delete Connection", role: .destructive) {
                deleteConnection()
            }
        }
    }

    // MARK: - Helper Functions

    private func calculatePortPosition(
        block: SignalBlock,
        portName: String,
        isOutput: Bool
    ) -> CGPoint {
        let blockWidth: CGFloat = 120
        let portSpacing: CGFloat = 20

        if isOutput {
            guard let portIndex = block.outputPorts.firstIndex(where: { $0.name == portName }) else {
                return block.position
            }
            
            let portsCount: Int = block.outputPorts.count
            let startY = block.position.y - (CGFloat(portsCount - 1) * portSpacing) / 2
            let portY = startY + CGFloat(portIndex) * portSpacing
            let portX = block.position.x + blockWidth / 2
            return CGPoint(x: portX, y: portY)
        } else {
            guard let portIndex = block.inputPorts.firstIndex(where: { $0.name == portName }) else {
                return block.position
            }
            
            let portsCount: Int = block.inputPorts.count
            let startY = block.position.y - (CGFloat(portsCount - 1) * portSpacing) / 2
            let portY = startY + CGFloat(portIndex) * portSpacing
            let portX = block.position.x - blockWidth / 2
            return CGPoint(x: portX, y: portY)
        }
    }

    private func calculateMidpoint(from startPoint: CGPoint, to endPoint: CGPoint) -> CGPoint {
        // Calculate midpoint of the curve (approximate)
        let controlPoint1 = CGPoint(
            x: startPoint.x + connectionCurvature,
            y: startPoint.y
        )
        let controlPoint2 = CGPoint(
            x: endPoint.x - connectionCurvature,
            y: endPoint.y
        )

        // Bezier curve midpoint approximation
        let midpointProgress = 0.5
        let midpointX = pow(1 - midpointProgress, 3) * startPoint.x +
                3 * pow(1 - midpointProgress, 2) * midpointProgress * controlPoint1.x +
                3 * (1 - midpointProgress) * pow(midpointProgress, 2) * controlPoint2.x +
                pow(midpointProgress, 3) * endPoint.x

        let midpointY = pow(1 - midpointProgress, 3) * startPoint.y +
                3 * pow(1 - midpointProgress, 2) * midpointProgress * controlPoint1.y +
                3 * (1 - midpointProgress) * pow(midpointProgress, 2) * controlPoint2.y +
                pow(midpointProgress, 3) * endPoint.y

        return CGPoint(x: midpointX, y: midpointY - 20) // Offset for label positioning
    }

    private func startSignalFlowAnimation() {
        withAnimation(.linear(duration: flowSpeed).repeatForever(autoreverses: false)) {
            flowAnimation = true
            signalFlow = 1.0
        }
        updateConnectionStrength()
    }

    private func updateConnectionStrength() {
        // Simulate connection strength based on signal activity
        // In a real implementation, this would be based on actual signal levels
        let randomVariation = Double.random(in: 0.8...1.0)
        withAnimation(.easeInOut(duration: 0.5)) {
            connectionStrength = 0.7 * randomVariation
        }
    }

    private func inspectConnection() {
        // Show detailed connection information
        print("Inspecting connection: \(connection)")
        // In a real implementation, this would open a detailed inspector
    }

    private func toggleConnectionMute() {
        // Toggle connection muting
        print("Toggling mute for connection: \(connection.id)")
        // In a real implementation, this would affect audio routing
    }

    private func deleteConnection() {
        Task {
            try? await blockManager.removeConnection(id: connection.id)
        }
    }
}

#Preview {
    let sampleConnection = BlockConnection(
        outputBlockId: UUID(),
        outputPort: "signal",
        inputBlockId: UUID(),
        inputPort: "frequency"
    )

    let sampleBlocks = [
        SignalBlock(
            type: .sineOscillator,
            title: "Sine Wave",
            position: CGPoint(x: 100, y: 100),
            parameters: [:],
            inputPorts: [InputPort(name: "frequency", displayName: "Frequency", signalType: .frequency, isRequired: false, defaultValue: nil)],
            outputPorts: [OutputPort(name: "signal", displayName: "Signal", signalType: .audio, isRequired: false, defaultValue: nil)]
        ),
        SignalBlock(
            type: .triangleOscillator,
            title: "Triangle LFO",
            position: CGPoint(x: 300, y: 100),
            parameters: [:],
            inputPorts: [InputPort(name: "frequency", displayName: "Frequency", signalType: .frequency, isRequired: false, defaultValue: nil)],
            outputPorts: [OutputPort(name: "signal", displayName: "Signal", signalType: .audio, isRequired: false, defaultValue: nil)]
        )
    ]

    // Update connection with actual block IDs
    let updatedConnection = BlockConnection(
        outputBlockId: sampleBlocks[0].id,
        outputPort: "signal",
        inputBlockId: sampleBlocks[1].id,
        inputPort: "frequency"
    )

    let mockBlockManager = BlockManagerServiceImpl(audioService: MockAudioBlockService())
    ConnectionView(
        connection: updatedConnection,
        blocks: sampleBlocks,
        canvasService: BlockCanvasServiceImpl(blockManagerService: mockBlockManager),
        blockManager: mockBlockManager
    )
    .frame(width: 500, height: 300)
    .background(Color.gray.opacity(0.1))
}
