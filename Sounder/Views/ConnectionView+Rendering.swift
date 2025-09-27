import SwiftUI

extension ConnectionView {
    // MARK: - Block References

    var outputBlock: SignalBlock? {
        blocks.first { $0.id == connection.outputBlockId }
    }

    var inputBlock: SignalBlock? {
        blocks.first { $0.id == connection.inputBlockId }
    }

    // MARK: - Connection Path

    func connectionPath(from startPoint: CGPoint, to endPoint: CGPoint) -> some View {
        Canvas { context, _ in
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

    func drawConnectionCurve(
        context: GraphicsContext,
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        strength: Double,
        isHovered: Bool
    ) {
        let path: Path = createConnectionPath(from: startPoint, to: endPoint)

        // Connection shadow
        if isHovered {
            context.stroke(
                path,
                with: .color(.black.opacity(0.3)),
                style: StrokeStyle(lineWidth: 6, lineCap: .round)
            )
        }

        // Main connection line
        let lineWidth: Double = isHovered ? 4.0 : 2.0
        let opacity: Double = strength * (isHovered ? 1.0 : 0.8)

        context.stroke(
            path,
            with: .color(connectionColor.opacity(opacity)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )

        // Connection strength indicator (line thickness variation)
        if strength > 0.1 {
            let strengthPath: Path = createConnectionPath(from: startPoint, to: endPoint)
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

    func createConnectionPath(from startPoint: CGPoint, to endPoint: CGPoint) -> Path {
        Path { path in
            path.move(to: startPoint)

            // Calculate control points for smooth curve
            let controlPoint1: CGPoint = CGPoint(
                x: startPoint.x + connectionCurvature,
                y: startPoint.y
            )
            let controlPoint2: CGPoint = CGPoint(
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

    var connectionCurvature: CGFloat {
        let distance: CGFloat = abs((outputBlock?.position.x ?? 0) - (inputBlock?.position.x ?? 0))
        return min(max(CGFloat(distance * 0.3), 30), 100)
    }

    var connectionColor: Color {
        // Color based on signal type and strength
        let baseColor: Color = .blue
        let strengthFactor: Double = connectionStrength

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

    func signalFlowIndicator(from startPoint: CGPoint, to endPoint: CGPoint) -> some View {
        Canvas { context, _ in
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

    func drawSignalFlowDots(
        context: GraphicsContext,
        from startPoint: CGPoint,
        to endPoint: CGPoint
    ) {
        let path: Path = createConnectionPath(from: startPoint, to: endPoint)

        // Draw multiple flow dots
        for index in 0..<3 {
            let offset: Double = Double(index) * 0.33
            let progress: Double = fmod(signalFlow + offset, 1.0)

            if progress > 0 && progress < 1 {
                let point: CGPoint = interpolateAlongPath(
                    path: path,
                    progress: progress,
                    from: startPoint,
                    to: endPoint
                )

                let dotSize: CGFloat = CGFloat(4.0 * connectionStrength)
                let opacity: Double = sin(progress * .pi) * connectionStrength

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

    func interpolateAlongPath(
        path: Path,
        progress: Double,
        from startPoint: CGPoint,
        to endPoint: CGPoint
    ) -> CGPoint {
        // Simplified cubic bezier interpolation
        let interpolationProgress: CGFloat = CGFloat(progress)
        let controlPoint1: CGPoint = CGPoint(
            x: startPoint.x + connectionCurvature,
            y: startPoint.y
        )
        let controlPoint2: CGPoint = CGPoint(
            x: endPoint.x - connectionCurvature,
            y: endPoint.y
        )

        let xPosition: CGFloat = pow(1 - interpolationProgress, 3) * startPoint.x +
            3 * pow(1 - interpolationProgress, 2) * interpolationProgress * controlPoint1.x +
            3 * (1 - interpolationProgress) * pow(interpolationProgress, 2) * controlPoint2.x +
            pow(interpolationProgress, 3) * endPoint.x

        let yPosition: CGFloat = pow(1 - interpolationProgress, 3) * startPoint.y +
            3 * pow(1 - interpolationProgress, 2) * interpolationProgress * controlPoint1.y +
            3 * (1 - interpolationProgress) * pow(interpolationProgress, 2) * controlPoint2.y +
            pow(interpolationProgress, 3) * endPoint.y

        return CGPoint(x: xPosition, y: yPosition)
    }

    // MARK: - Connection Label

    func connectionLabel(midpoint: CGPoint) -> some View {
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

    /// Context menu presenting quick actions for the connection.
    var connectionContextMenu: some View {
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

    func calculatePortPosition(
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
            let startY: CGFloat = block.position.y - (CGFloat(portsCount - 1) * portSpacing) / 2
            let portY: CGFloat = startY + CGFloat(portIndex) * portSpacing
            let portX: CGFloat = block.position.x + blockWidth / 2
            return CGPoint(x: portX, y: portY)
        } else {
            guard let portIndex = block.inputPorts.firstIndex(where: { $0.name == portName }) else {
                return block.position
            }

            let portsCount: Int = block.inputPorts.count
            let startY: CGFloat = block.position.y - (CGFloat(portsCount - 1) * portSpacing) / 2
            let portY: CGFloat = startY + CGFloat(portIndex) * portSpacing
            let portX: CGFloat = block.position.x - blockWidth / 2
            return CGPoint(x: portX, y: portY)
        }
    }

    func calculateMidpoint(from startPoint: CGPoint, to endPoint: CGPoint) -> CGPoint {
        // Calculate midpoint of the curve (approximate)
        let controlPoint1: CGPoint = CGPoint(
            x: startPoint.x + connectionCurvature,
            y: startPoint.y
        )
        let controlPoint2: CGPoint = CGPoint(
            x: endPoint.x - connectionCurvature,
            y: endPoint.y
        )

        // Bezier curve midpoint approximation
        let midpointProgress: CGFloat = 0.5
        let midpointX: CGFloat = pow(1 - midpointProgress, 3) * startPoint.x +
            3 * pow(1 - midpointProgress, 2) * midpointProgress * controlPoint1.x +
            3 * (1 - midpointProgress) * pow(midpointProgress, 2) * controlPoint2.x +
            pow(midpointProgress, 3) * endPoint.x

        let midpointY: CGFloat = pow(1 - midpointProgress, 3) * startPoint.y +
            3 * pow(1 - midpointProgress, 2) * midpointProgress * controlPoint1.y +
            3 * (1 - midpointProgress) * pow(midpointProgress, 2) * controlPoint2.y +
            pow(midpointProgress, 3) * endPoint.y

        return CGPoint(x: midpointX, y: midpointY - 20)
    }

    func startSignalFlowAnimation() {
        withAnimation(.linear(duration: flowSpeed).repeatForever(autoreverses: false)) {
            flowAnimation = true
            signalFlow = 1.0
        }
        updateConnectionStrength()
    }

    func updateConnectionStrength() {
        // Simulate connection strength based on signal activity
        // In a real implementation, this would be based on actual signal levels
        let randomVariation: Double = Double.random(in: 0.8...1.0)
        withAnimation(.easeInOut(duration: 0.5)) {
            connectionStrength = 0.7 * randomVariation
        }
    }

    func inspectConnection() {
        // Show detailed connection information
        print("Inspecting connection: \(connection)")
        // In a real implementation, this would open a detailed inspector
    }

    func toggleConnectionMute() {
        // Toggle connection muting
        print("Toggling mute for connection: \(connection.id)")
        // In a real implementation, this would affect audio routing
    }

    func deleteConnection() {
        Task {
            try? await blockManager.removeConnection(id: connection.id)
        }
    }
}
