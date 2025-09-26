import SwiftUI
import UniformTypeIdentifiers

/// Main canvas view for the block-based signal generator interface
/// Supports drag-and-drop, zoom, pan, and real-time connection drawing
struct BlockCanvasView: View {
    @EnvironmentObject private var canvasService: BlockCanvasServiceImpl
    @EnvironmentObject private var blockManager: BlockManagerServiceImpl
    @State private var selectedBlock: SignalBlock?
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var connectionInProgress: (blockId: UUID, portName: String, isOutput: Bool)?
    @State private var showingBlockLibrary: Bool = false

    // Canvas interaction state
    @State private var canvasOffset: CGSize = .zero
    @State private var lastCanvasOffset: CGSize = .zero
    @State private var canvasScale: CGFloat = 1.0
    @GestureState private var magnifyBy: CGFloat = 1.0
    @GestureState private var panBy: CGSize = CGSize.zero



    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Canvas background
                canvasBackground

                // Canvas content
                canvasContent
                    .scaleEffect(canvasScale * magnifyBy)
                    .offset(
                        x: canvasOffset.width + panBy.width,
                        y: canvasOffset.height + panBy.height
                    )
                    .clipped()

                // Connection preview overlay
                connectionPreviewOverlay

                // Canvas controls overlay
                canvasControlsOverlay
            }
            .gesture(
                SimultaneousGesture(
                    // Pan gesture
                    DragGesture()
                        .updating($panBy) { value, state, _ in
                            if connectionInProgress == nil {
                                state = value.translation
                            }
                        }
                        .onEnded { value in
                            if connectionInProgress == nil {
                                canvasOffset.width += value.translation.width
                                canvasOffset.height += value.translation.height
                            }
                        },

                    // Zoom gesture
                    MagnificationGesture()
                        .updating($magnifyBy) { value, state, _ in
                            state = value
                        }
                        .onEnded { value in
                            let newScale: CGFloat = canvasScale * value
                            canvasScale = min(max(newScale, 0.5), 3.0)
                        }
                )
            )
            .onDrop(of: [UTType.text], isTargeted: nil) { providers, location in
                handleBlockDrop(providers: providers, location: location, geometry: geometry)
            }
            .onReceive(canvasService.selectionChanged) { block in
                selectedBlock = block
            }
            .onReceive(canvasService.connectionStarted) { connection in
                connectionInProgress = (
                    blockId: connection.sourceBlockId,
                    portName: connection.sourcePort,
                    isOutput: true
                )
            }
            .onReceive(canvasService.connectionCompleted) { _ in
                connectionInProgress = nil
            }
            .sheet(isPresented: $showingBlockLibrary) {
                BlockLibraryView(blockManager: blockManager)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        // Canvas size is initialized elsewhere
        .onAppear {
            // canvasService.updateCanvasSize(CGSize(width: 2000, height: 1500))
        }
    }

    // MARK: - Canvas Background

    private var canvasBackground: some View {
        ZStack {
            // Grid background
            Canvas { context, size in
                drawGrid(context: context, size: size)
            }
            .background(Color(NSColor.controlBackgroundColor))

            // Drop zone indicator
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.05))
                .stroke(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [5]))
                .overlay(
                    Text("Drop blocks here or press + to add")
                        .foregroundColor(.secondary)
                        .font(.title2)
                )
                .task {
                    let config = await blockManager.getCurrentConfiguration()
                    // Note: This won't update the view automatically, need to handle state properly
                }
        }
    }

    // MARK: - Canvas Content

    private var canvasContent: some View {
        ZStack {
            // Connections layer
            ForEach(blockConnections) { connection in
                ConnectionView(
                    connection: connection,
                    blocks: blockManager.currentConfiguration.blocks,
                    canvasService: canvasService,
                    blockManager: blockManager
                )
            }

            // Blocks layer
            ForEach(blockManager.currentConfiguration.blocks) { block in
                BlockView(
                    block: block,
                    isSelected: selectedBlock?.id == block.id,
                    blockManager: blockManager,
                    canvasService: canvasService
                )
                .position(block.position)
                .onTapGesture {
                    selectedBlock = block
                }
            }
        }
    }

    // MARK: - Connection Preview

    private var connectionPreviewOverlay: some View {
        Group {
            if let connection = connectionInProgress {
                Canvas { context, size in
                    drawConnectionPreview(
                        context: context,
                        size: size,
                        connection: connection
                    )
                }
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Canvas Controls

    private var canvasControlsOverlay: some View {
        VStack {
            HStack {
                // Add block button
                Button(action: { showingBlockLibrary = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .help("Add Block")

                Spacer()

                // Canvas info
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Blocks: \(blockManager.currentConfiguration.blocks.count)")
                    Text("Zoom: \(Int(canvasScale * 100))%")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .cornerRadius(6)
            }
            .padding()

            Spacer()

            HStack {
                Spacer()

                // Canvas controls
                VStack(spacing: 8) {
                    // Reset zoom
                    Button(action: resetCanvas) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("Reset View")

                    // Fit to content
                    Button(action: fitToContent) {
                        Image(systemName: "rectangle.compress.vertical")
                    }
                    .help("Fit to Content")

                    // Clear canvas
                    Button(action: {
                        Task {
                            await blockManager.clearConfiguration()
                        }
                    }) {
                        Image(systemName: "trash")
                    }
                    .help("Clear Canvas")
                    .disabled(blockManager.currentConfiguration.blocks.isEmpty)
                }
                .buttonStyle(.borderless)
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .cornerRadius(8)
                .padding()
            }
        }
    }

    // MARK: - Drawing Functions

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let gridSize: CGFloat = 20 * canvasScale
        let lineWidth: CGFloat = 0.5

        // Calculate visible grid range
        let startX: CGFloat = floor(-canvasOffset.width / gridSize) * gridSize
        let startY: CGFloat = floor(-canvasOffset.height / gridSize) * gridSize
        let endX: CGFloat = startX + size.width + gridSize
        let endY: CGFloat = startY + size.height + gridSize

        context.stroke(
            Path { path in
                // Vertical lines
                var xPosition: CGFloat = startX
                while xPosition <= endX {
                    path.move(to: CGPoint(x: xPosition + canvasOffset.width, y: 0))
                    path.addLine(to: CGPoint(x: xPosition + canvasOffset.width, y: size.height))
                    xPosition += gridSize
                }

                // Horizontal lines
                var yPosition: CGFloat = startY
                while yPosition <= endY {
                    path.move(to: CGPoint(x: 0, y: yPosition + canvasOffset.height))
                    path.addLine(to: CGPoint(x: size.width, y: yPosition + canvasOffset.height))
                    yPosition += gridSize
                }
            },
            with: .color(.gray.opacity(0.2)),
            lineWidth: lineWidth
        )
    }

    private func drawConnectionPreview(
        context: GraphicsContext,
        size: CGSize,
        connection: (blockId: UUID, portName: String, isOutput: Bool)
    ) {
        guard let block = blockManager.currentConfiguration.blocks.first(where: { $0.id == connection.blockId }) else { return }
        let mouseLocation = canvasService.canvasState.viewportCenter

        let startPoint: CGPoint = calculatePortPosition(
            block: block,
            portName: connection.portName,
            isOutput: connection.isOutput
        )

        let endPoint: CGPoint = CGPoint(
            x: (mouseLocation.x - canvasOffset.width) / canvasScale,
            y: (mouseLocation.y - canvasOffset.height) / canvasScale
        )

        context.stroke(
            Path { path in
                path.move(to: startPoint)
                path.addCurve(
                    to: endPoint,
                    control1: CGPoint(x: startPoint.x + 50, y: startPoint.y),
                    control2: CGPoint(x: endPoint.x - 50, y: endPoint.y)
                )
            },
            with: .color(.accentColor.opacity(0.6)),
            style: StrokeStyle(lineWidth: 2, dash: [5])
        )
    }

    // MARK: - Helper Functions

    private func calculatePortPosition(block: SignalBlock, portName: String, isOutput: Bool) -> CGPoint {
        let blockWidth: CGFloat = 120
        let blockHeight: CGFloat = 80
        let portSpacing: CGFloat = 20

        let ports: [String] = isOutput ? block.outputPorts.map({$0.name}) : block.inputPorts.map({$0.name})
        guard let portIndex = ports.firstIndex(of: portName) else {
            return block.position
        }

        let portsCount: Int = ports.count
        let startY: CGFloat = block.position.y - (CGFloat(portsCount - 1) * portSpacing) / 2
        let portY: CGFloat = startY + CGFloat(portIndex) * portSpacing

        let portX: CGFloat = isOutput ?
            block.position.x + blockWidth / 2 :
            block.position.x - blockWidth / 2

        return CGPoint(x: portX, y: portY)
    }

    private func handleBlockDrop(
        providers: [NSItemProvider],
        location: CGPoint,
        geometry: GeometryProxy
    ) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, error in
                    if let data = item as? Data,
                       let blockTypeString = String(data: data, encoding: .utf8),
                       let blockType = BlockType(rawValue: blockTypeString) {

                        Task { @MainActor in
                            let canvasLocation: CGPoint = CGPoint(
                                x: (location.x - canvasOffset.width) / canvasScale,
                                y: (location.y - canvasOffset.height) / canvasScale
                            )

                            do {
                                _ = try await blockManager.createBlock(
                                    type: blockType,
                                    at: canvasLocation
                                )
                            } catch {
                                print("Failed to create block: \(error)")
                            }
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    private func resetCanvas() {
        withAnimation(.easeInOut(duration: 0.3)) {
            canvasOffset = .zero
            canvasScale = 1.0
        }
    }

    private func fitToContent() {
        guard !blockManager.currentConfiguration.blocks.isEmpty else { return }

        let blocks: [SignalBlock] = blockManager.currentConfiguration.blocks
        let minX: CGFloat = blocks.map { $0.position.x }.min() ?? 0
        let maxX: CGFloat = blocks.map { $0.position.x }.max() ?? 0
        let minY: CGFloat = blocks.map { $0.position.y }.min() ?? 0
        let maxY: CGFloat = blocks.map { $0.position.y }.max() ?? 0

        let contentWidth: CGFloat = maxX - minX + 200 // padding
        let contentHeight: CGFloat = maxY - minY + 200 // padding

        withAnimation(.easeInOut(duration: 0.5)) {
            canvasScale = min(1.0, min(800 / contentWidth, 600 / contentHeight))
            canvasOffset = CGSize(
                width: -(minX + maxX) / 2 * canvasScale + 400,
                height: -(minY + maxY) / 2 * canvasScale + 300
            )
        }
    }

    private func clearCanvas() {
        Task {
            await blockManager.clearConfiguration()
            selectedBlock = nil
            connectionInProgress = nil
        }
    }

    private var blockConnections: [BlockConnection] {
        blockManager.currentConfiguration.connections.toBlockConnections()
    }
}

#Preview {
    let audioService = MockAudioBlockService()
    let blockManager = BlockManagerServiceImpl(audioService: audioService)
    let canvasService = BlockCanvasServiceImpl(blockManagerService: blockManager)

    return BlockCanvasView()
        .environmentObject(canvasService)
        .environmentObject(blockManager)
        .frame(width: 800, height: 600)
}
