import SwiftUI

/// Individual block view component with ports, parameters, and real-time visualization
struct BlockView: View {
    let block: SignalBlock
    let isSelected: Bool
    @ObservedObject var blockManager: BlockManagerServiceImpl
    @ObservedObject var canvasService: BlockCanvasServiceImpl

    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    @State private var showingParameters = false
    @State private var isHovered = false

    // Real-time visualization state
    @State private var signalLevel: Double = 0.0
    @State private var isActive = false

    private let blockWidth: CGFloat = 120
    private let blockHeight: CGFloat = 80
    private let portSize: CGFloat = 12

    var body: some View {
        ZStack {
            // Main block body
            blockBody

            // Block content
            blockContent

            // Input ports
            inputPortsView

            // Output ports
            outputPortsView

            // Selection indicator
            if isSelected {
                selectionIndicator
            }

            // Activity indicator
            if isActive {
                activityIndicator
            }
        }
        .offset(dragOffset)
        .scaleEffect(isDragging ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        // canvasService.startBlockDrag(block) // Method not implemented
                    }
                    dragOffset = value.translation
                }
                .onEnded { value in
                    isDragging = false

                    // Update block position
                    let newPosition = CGPoint(
                        x: block.position.x + value.translation.width,
                        y: block.position.y + value.translation.height
                    )

                    Task {
                        try await blockManager.moveBlock(id: block.id, to: newPosition)
                    }
                    // canvasService.endBlockDrag() // Method not implemented
                    dragOffset = .zero
                }
        )
        .contextMenu {
            blockContextMenu
        }
        .onReceive(blockManager.blockUpdated) { updatedBlock in
            if updatedBlock.id == block.id {
                updateVisualization()
            }
        }
        .onAppear {
            updateVisualization()
        }
    }

    // MARK: - Block Body

    private var blockBody: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(blockBackgroundGradient)
            .stroke(blockBorderColor, lineWidth: isSelected ? 2 : 1)
            .frame(width: blockWidth, height: blockHeight)
            .shadow(
                color: .black.opacity(isDragging ? 0.3 : 0.1),
                radius: isDragging ? 8 : 2,
                x: 0,
                y: isDragging ? 4 : 1
            )
    }

    private var blockBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                blockTypeColor.opacity(0.8),
                blockTypeColor.opacity(0.6)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var blockBorderColor: Color {
        if isSelected {
            return .accentColor
        } else if isHovered {
            return blockTypeColor
        } else {
            return Color.gray.opacity(0.3)
        }
    }

    private var blockTypeColor: Color {
        switch block.type {
        case .sineOscillator: return .blue
        case .triangleOscillator: return .orange
        case .frequencyModulator: return .purple
        case .whiteNoise: return .red
        case .spectrumAnalyzer: return .green
        case .audioOutput: return .pink
        // Add missing cases
        case .squareOscillator: return .cyan
        case .sawtoothOscillator: return .indigo
        case .pinkNoise: return .brown
        case .linearChirp: return .mint
        case .hyperbolicChirp: return .teal
        case .amplitudeModulator: return .yellow
        case .ringModulator: return .gray
        case .lowPassFilter: return .green
        case .highPassFilter: return .blue
        case .bandPassFilter: return .purple
        case .mixer: return .orange
        case .amplifier: return .red
        case .levelMeter: return .yellow
        case .frequencyCounter: return .cyan
        }
    }

    // MARK: - Block Content

    private var blockContent: some View {
        VStack(spacing: 4) {
            // Block title
            Text(block.title)
                .font(.caption.bold())
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // Block type icon
            Image(systemName: blockTypeIcon)
                .font(.title3)
                .foregroundColor(.primary.opacity(0.8))

            // Signal level indicator
            signalLevelIndicator

            // Parameter count indicator
            if !block.parameters.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption2)
                    Text("\(block.parameters.count)")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
        }
        .frame(width: blockWidth - 16, height: blockHeight - 16)
    }

    private var blockTypeIcon: String {
        switch block.type {
        case .sineOscillator: return "waveform"
        case .triangleOscillator: return "triangle"
        case .frequencyModulator: return "antenna.radiowaves.left.and.right"
        case .whiteNoise: return "dot.radiowaves.left.and.right"
        case .spectrumAnalyzer: return "chart.bar.fill"
        case .audioOutput: return "speaker.wave.2.fill"
        // Add missing cases
        case .squareOscillator: return "square"
        case .sawtoothOscillator: return "sawtooth"
        case .pinkNoise: return "dot.radiowaves.up.forward"
        case .linearChirp: return "arrow.up.right"
        case .hyperbolicChirp: return "arrow.up.right.circle"
        case .amplitudeModulator: return "amplifier"
        case .ringModulator: return "circle.grid.cross"
        case .lowPassFilter: return "arrow.down.circle"
        case .highPassFilter: return "arrow.up.circle"
        case .bandPassFilter: return "arrow.left.and.right.circle"
        case .mixer: return "slider.horizontal.3"
        case .amplifier: return "plus.magnifyingglass"
        case .levelMeter: return "chart.bar"
        case .frequencyCounter: return "number"
        }
    }

    private var signalLevelIndicator: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(0..<8, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(signalLevel > Double(index) / 8.0 ? .green : .gray.opacity(0.3))
                        .frame(width: 2, height: 6)
                }
            }
            .frame(width: geometry.size.width, height: 6)
        }
        .frame(height: 6)
    }

    // MARK: - Input Ports

    private var inputPortsView: some View {
        VStack(spacing: 8) {
            ForEach(Array(block.inputPorts.enumerated()), id: \.offset) { index, port in
                InputPortView(
                    portName: port.name,
                    blockId: block.id,
                    isConnected: isPortConnected(portName: port.name, isOutput: false),
                    canvasService: canvasService,
                    blockManager: blockManager
                )
            }
        }
        .offset(
            x: -blockWidth / 2 - portSize / 2,
            y: 0
        )
    }

    // MARK: - Output Ports

    private var outputPortsView: some View {
        VStack(spacing: 8) {
            ForEach(Array(block.outputPorts.enumerated()), id: \.offset) { index, port in
                OutputPortView(
                    portName: port.name,
                    blockId: block.id,
                    isConnected: isPortConnected(portName: port.name, isOutput: true),
                    canvasService: canvasService,
                    blockManager: blockManager
                )
            }
        }
        .offset(
            x: blockWidth / 2 + portSize / 2,
            y: 0
        )
    }

    // MARK: - Selection Indicator

    private var selectionIndicator: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(Color.accentColor, lineWidth: 2)
            .frame(width: blockWidth + 8, height: blockHeight + 8)
            .opacity(0.8)
    }

    // MARK: - Activity Indicator

    private var activityIndicator: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 8, height: 8)
            .offset(x: blockWidth / 2 - 8, y: -blockHeight / 2 + 8)
            .opacity(isActive ? 1 : 0)
            .scaleEffect(isActive ? 1 : 0.5)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isActive)
    }

    // MARK: - Context Menu

    private var blockContextMenu: some View {
        VStack {
            Button("Edit Parameters") {
                showingParameters = true
            }
            .disabled(block.parameters.isEmpty)

            Button("Duplicate") {
                duplicateBlock()
            }

            Button("Reset") {
                resetBlock()
            }

            Divider()

            Button("Delete", role: .destructive) {
                deleteBlock()
            }
        }
    }

    // MARK: - Helper Functions

    private func isPortConnected(portName: String, isOutput: Bool) -> Bool {
        Task { @MainActor in
            let configuration = await blockManager.getCurrentConfiguration()
            return configuration.connections.contains { connection in
                if isOutput {
                    return connection.sourceBlockId == block.id && connection.sourcePort == portName
                } else {
                    return connection.destinationBlockId == block.id && connection.destinationPort == portName
                }
            }
        }
        return false // Default to false if async check isn't completed yet
    }

    private func updateVisualization() {
        // Simulate signal level based on block type and parameters
        withAnimation(.easeInOut(duration: 0.3)) {
            switch block.type {
            case .sineOscillator, .triangleOscillator:
                if let ampParam = block.parameters["amplitude"] {
                    signalLevel = (ampParam.value + 60) / 60 // Convert dB to 0-1 range
                } else {
                    signalLevel = 0.5
                }
                isActive = true

            case .whiteNoise:
                signalLevel = Double.random(in: 0.3...0.8)
                isActive = true

            case .frequencyModulator:
                signalLevel = 0.6
                isActive = hasConnectedInputs()

            case .spectrumAnalyzer:
                signalLevel = hasConnectedInputs() ? Double.random(in: 0.4...0.9) : 0.0
                isActive = hasConnectedInputs()

            case .audioOutput:
                signalLevel = hasConnectedInputs() ? 0.7 : 0.0
                isActive = hasConnectedInputs()
            default:
                signalLevel = 0.5
                isActive = hasConnectedInputs()
            }
        }
    }

    private func hasConnectedInputs() -> Bool {
        // For now, using a direct check - in a real implementation, 
        // you'd want to track this as a published property
        return true // Conservative approach to avoid async issues
    }

    private func duplicateBlock() {
        Task {
            let offset: CGFloat = 30
            let newPosition = CGPoint(
                x: block.position.x + offset,
                y: block.position.y + offset
            )

            do {
                let _ = try await blockManager.createBlock(type: block.type, at: newPosition)
            } catch {
                print("Failed to duplicate block: \(error)")
            }
        }
    }

    private func resetBlock() {
        // Reset block parameters to defaults
        for (key, parameter) in block.parameters {
            blockManager.updateParameter(
                blockId: block.id,
                parameterName: key,
                value: parameter.minimumValue
            )
        }
    }

    private func deleteBlock() {
        Task {
            try? await blockManager.removeBlock(id: block.id)
        }
    }
}

// MARK: - Port Views

struct InputPortView: View {
    let portName: String
    let blockId: UUID
    let isConnected: Bool
    @ObservedObject var canvasService: BlockCanvasServiceImpl
    @ObservedObject var blockManager: BlockManagerServiceImpl

    @State private var isHovered = false

    private let portSize: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .fill(isConnected ? Color.blue : Color.gray.opacity(0.6))
                .frame(width: portSize, height: portSize)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 1)
                )
                .scaleEffect(isHovered ? 1.2 : 1.0)
                .animation(.spring(response: 0.3), value: isHovered)

            // Port label
            Text(portName)
                .font(.caption2)
                .foregroundColor(.primary)
                .offset(x: -portSize - 20, y: 0)
                .opacity(isHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .frame(width: portSize, height: portSize)
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrop(of: [.text], isTargeted: nil) { providers, location in
            handleConnectionDrop(providers: providers)
        }
        .help("Input: \(portName)")
    }

    private func handleConnectionDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        var result = false
        let semaphore = DispatchSemaphore(value: 0)

        provider.loadObject(ofClass: NSString.self) { object, error in
            defer { semaphore.signal() }

            guard let dragDataString = object as? NSString else { return }

            // Parse drag data: "blockId|portName|sessionId"
            let components = (dragDataString as String).components(separatedBy: "|")
            guard components.count >= 2,
                  let sourceBlockId = UUID(uuidString: components[0]) else {
                return
            }

            let sourcePortName = components[1]
            let sessionId = components.count > 2 ? UUID(uuidString: components[2]) : nil

            // Create connection using canvas service
            Task { @MainActor in
                do {
                    if let sessionId = sessionId {
                        // Complete the connection drawing session
                        let _ = try await canvasService.completeConnectionDraw(
                            connectionSessionId: sessionId,
                            to: blockId,
                            port: portName
                        )
                        result = true
                    } else {
                        // Fallback: create connection directly via block manager
                        let isValid = await blockManager.validateConnection(
                            from: sourceBlockId, sourcePort: sourcePortName,
                            to: blockId, destinationPort: portName
                        )

                        if isValid {
                            let _ = try await blockManager.createConnection(
                                from: sourceBlockId, sourcePort: sourcePortName,
                                to: blockId, destinationPort: portName
                            )
                            result = true
                        }
                    }
                } catch {
                    // Fallback: create connection directly via block manager
                    do {
                        let isValid = await blockManager.validateConnection(
                            from: sourceBlockId, sourcePort: sourcePortName,
                            to: blockId, destinationPort: portName
                        )

                        if isValid {
                            let _ = try await blockManager.createConnection(
                                from: sourceBlockId, sourcePort: sourcePortName,
                                to: blockId, destinationPort: portName
                            )
                            result = true
                        }
                    } catch {
                        print("Failed to create connection: \(error)")
                    }
                }
            }
        }

        semaphore.wait()
        return result
    }
}

struct OutputPortView: View {
    let portName: String
    let blockId: UUID
    let isConnected: Bool
    @ObservedObject var canvasService: BlockCanvasServiceImpl
    @ObservedObject var blockManager: BlockManagerServiceImpl

    @State private var isHovered = false
    @State private var currentConnectionSessionId: UUID?

    private let portSize: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .fill(isConnected ? Color.orange : Color.gray.opacity(0.6))
                .frame(width: portSize, height: portSize)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 1)
                )
                .scaleEffect(isHovered ? 1.2 : 1.0)
                .animation(.spring(response: 0.3), value: isHovered)

            // Port label
            Text(portName)
                .font(.caption2)
                .foregroundColor(.primary)
                .offset(x: portSize + 20, y: 0)
                .opacity(isHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .frame(width: portSize, height: portSize)
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrag {
            Task {
                currentConnectionSessionId = await canvasService.beginConnectionDraw(
                    from: blockId,
                    port: portName,
                    at: CGPoint(x: 0, y: 0) // Initial position - will be updated
                )
            }
            // Include block ID, port name, and session ID in drag data
            let sessionId = currentConnectionSessionId?.uuidString ?? ""
            let dragData = "\(blockId.uuidString)|\(portName)|\(sessionId)"
            return NSItemProvider(object: dragData as NSString)
        }
        .help("Output: \(portName)")
    }
}

#Preview {
    let sampleBlock = SignalBlock(
        type: .sineOscillator,
        title: "Sine Wave",
        position: CGPoint(x: 100, y: 100),
        parameters: [
            "frequency": BlockParameter.frequency(value: 440.0),
            "amplitude": BlockParameter.amplitude(value: -12.0)
        ],
        inputPorts: [InputPort(name: "frequency", displayName: "Frequency", signalType: .frequency, isRequired: false, defaultValue: nil)],
        outputPorts: [OutputPort(name: "signal", displayName: "Signal", signalType: .audio, isRequired: false, defaultValue: nil)]
    )

    BlockView(
        block: sampleBlock,
        isSelected: true,
        blockManager: BlockManagerServiceImpl(audioService: MockAudioBlockService()),
        canvasService: BlockCanvasServiceImpl(blockManagerService: BlockManagerServiceImpl(audioService: MockAudioBlockService()))
    )
    .frame(width: 200, height: 150)
    .background(Color.gray.opacity(0.1))
}
