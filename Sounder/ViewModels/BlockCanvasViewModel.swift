import SwiftUI
import Combine

/// View model for the block canvas, managing canvas state and coordinating block operations
@MainActor
class BlockCanvasViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var canvasSize: CGSize = CGSize(width: 2000, height: 1500)
    @Published var canvasOffset: CGSize = .zero
    @Published var canvasScale: CGFloat = 1.0
    @Published var selectedBlocks: Set<UUID> = []
    @Published var isDragging: Bool = false
    @Published var isConnecting: Bool = false
    @Published var showingGrid: Bool = true
    @Published var snapToGrid: Bool = true

    // Connection state
    @Published var activeConnection: PendingConnection?
    @Published var hoveredPort: PortReference?
    @Published var connectionPreviewPath: CGPath?

    // Selection and interaction
    @Published var selectionRectangle: CGRect?
    @Published var lastClickPosition: CGPoint = .zero
    @Published var dragStartPositions: [UUID: CGPoint] = [:]

    // Canvas tools
    @Published var currentTool: CanvasTool = .select
    @Published var gridSize: CGFloat = 20
    @Published var showMinimap: Bool = false
    @Published var minimapPosition: MinimapPosition = .bottomRight

    // MARK: - Services

    private let blockManager: BlockManagerService
    private let canvasService: BlockCanvasService
    private var cancellables: Set<AnyCancellable> = Set<AnyCancellable>()

    // MARK: - State Management

    private var undoManager: UndoManager = UndoManager()
    private var actionHistory: [CanvasAction] = []
    private var redoStack: [CanvasAction] = []

    // MARK: - Initialization

    init(blockManager: BlockManagerService, canvasService: BlockCanvasService) {
        self.blockManager = blockManager
        self.canvasService = canvasService

        setupBindings()
        setupCanvasDefaults()
    }

    private func setupBindings() {
        // Subscribe to canvas service events
        canvasService.selectionChanged
            .sink { [weak self] block in
                self?.handleBlockSelection(block)
            }
            .store(in: &cancellables)

        canvasService.connectionStarted
            .sink { [weak self] connection in
                self?.startConnection((blockId: connection.sourceBlockId, portName: connection.sourcePort, isOutput: true))
            }
            .store(in: &cancellables)

        canvasService.connectionCompleted
            .sink { [weak self] success in
                self?.completeConnection(success)
            }
            .store(in: &cancellables)

        // Subscribe to block manager events for canvas updates
        NotificationCenter.default.publisher(for: .blockCreated)
            .sink { [weak self] notification in
                if let block = notification.object as? SignalBlock {
                    self?.handleBlockCreated(block)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .blockRemoved)
            .sink { [weak self] notification in
                if let blockId = notification.object as? UUID {
                    self?.handleBlockRemoved(blockId)
                }
            }
            .store(in: &cancellables)
    }

    private func setupCanvasDefaults() {
        // Set initial canvas state
        canvasOffset = CGSize(width: 400, height: 300) // Center view
        canvasScale = 1.0
        showingGrid = true
        snapToGrid = true
        gridSize = 20
    }

    // MARK: - Canvas Navigation

    func panCanvas(by delta: CGSize) {
        let newOffset: CGSize = CGSize(
            width: canvasOffset.width + delta.width,
            height: canvasOffset.height + delta.height
        )

        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
            canvasOffset = newOffset
        }

        recordAction(.canvasPan(from: canvasOffset, destination: newOffset))
    }

    func zoomCanvas(by factor: CGFloat, at point: CGPoint? = nil) {
        let newScale: CGFloat = min(max(canvasScale * factor, 0.25), 4.0)

        if let zoomPoint = point {
            // Zoom towards specific point
            let scaleDelta: CGFloat = newScale - canvasScale
            let offsetDelta: CGSize = CGSize(
                width: -(zoomPoint.x * scaleDelta),
                height: -(zoomPoint.y * scaleDelta)
            )

            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                canvasScale = newScale
                canvasOffset = CGSize(
                    width: canvasOffset.width + offsetDelta.width,
                    height: canvasOffset.height + offsetDelta.height
                )
            }
        } else {
            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                canvasScale = newScale
            }
        }

        recordAction(.canvasZoom(from: canvasScale, destination: newScale))
    }

    func resetCanvasView() {
        withAnimation(.easeInOut(duration: 0.5)) {
            canvasOffset = CGSize(width: 400, height: 300)
            canvasScale = 1.0
        }

        recordAction(.canvasReset)
    }

    func fitToContent() {
        Task {
            let configuration: BlockConfiguration = await blockManager.getCurrentConfiguration()
            guard !configuration.blocks.isEmpty else { return }

            let positions: [CGPoint] = configuration.blocks.map(\.position)
            let minX: CGFloat = positions.map(\.x).min() ?? 0
            let maxX: CGFloat = positions.map(\.x).max() ?? 0
            let minY: CGFloat = positions.map(\.y).min() ?? 0
            let maxY: CGFloat = positions.map(\.y).max() ?? 0

            let contentBounds: CGRect = CGRect(
                x: minX - 50,
                y: minY - 50,
                width: (maxX - minX) + 100,
                height: (maxY - minY) + 100
            )

            let targetScale: CGFloat = min(
                800 / contentBounds.width,
                600 / contentBounds.height,
                1.0
            )

            let targetOffset: CGSize = CGSize(
                width: -contentBounds.midX * targetScale + 400,
                height: -contentBounds.midY * targetScale + 300
            )

            withAnimation(.easeInOut(duration: 0.8)) {
                canvasScale = targetScale
                canvasOffset = targetOffset
            }
        }
    }

    // MARK: - Block Selection

    func selectBlock(_ blockId: UUID, addToSelection: Bool = false) {
        if addToSelection {
            selectedBlocks.insert(blockId)
        } else {
            selectedBlocks = [blockId]
        }

        recordAction(.blockSelection(selectedBlocks))
    }

    func deselectBlock(_ blockId: UUID) {
        selectedBlocks.remove(blockId)
        recordAction(.blockSelection(selectedBlocks))
    }

    func clearSelection() {
        let previousSelection: Set<UUID> = selectedBlocks
        selectedBlocks.removeAll()
        recordAction(.blockSelection(selectedBlocks))
    }

    func selectAll() {
        Task {
            let configuration: BlockConfiguration = await blockManager.getCurrentConfiguration()
            let allBlockIds: Set<UUID> = Set(configuration.blocks.map(\.id))
            selectedBlocks = allBlockIds
            recordAction(.blockSelection(selectedBlocks))
        }
    }

    private func handleBlockSelection(_ block: SignalBlock?) {
        if let block = block {
            selectBlock(block.id)
        } else {
            clearSelection()
        }
    }

    // MARK: - Block Operations

    func deleteSelectedBlocks() {
        Task {
            let blocksToDelete: [UUID] = Array(selectedBlocks)

            for blockId in blocksToDelete {
                do {
                    try await blockManager.removeBlock(id: blockId)
                } catch {
                    print("Failed to delete block \(blockId): \(error)")
                }
            }

            clearSelection()
            recordAction(.blocksDeleted(blocksToDelete))
        }
    }

    func duplicateSelectedBlocks() {
        Task {
            let configuration: BlockConfiguration = await blockManager.getCurrentConfiguration()
            let blocksToDuplicate: [SignalBlock] = configuration.blocks.filter { selectedBlocks.contains($0.id) }

            var newBlockIds: [UUID] = [UUID]()

            for block in blocksToDuplicate {
                do {
                    let offset: CGPoint = CGPoint(x: 30, y: 30)
                    let newPosition: CGPoint = CGPoint(
                        x: block.position.x + offset.x,
                        y: block.position.y + offset.y
                    )

                    let newBlock: SignalBlock = try await blockManager.createBlock(
                        type: block.type,
                        at: newPosition
                    )

                    // Copy parameters
                    for (paramName, parameter) in block.parameters {
                        try await blockManager.updateBlockParameter(
                            blockId: newBlock.id,
                            parameterName: paramName,
                            value: parameter.value
                        )
                    }

                    newBlockIds.append(newBlock.id)
                } catch {
                    print("Failed to duplicate block \(block.id): \(error)")
                }
            }

            // Select duplicated blocks
            selectedBlocks = Set(newBlockIds)
            recordAction(.blocksDuplicated(blocksToDuplicate.map(\.id), newBlockIds))
        }
    }

    private func handleBlockCreated(_ block: SignalBlock) {
        // Auto-select newly created blocks
        selectBlock(block.id)
    }

    private func handleBlockRemoved(_ blockId: UUID) {
        // Remove from selection if selected
        selectedBlocks.remove(blockId)
    }

    // MARK: - Connection Management

    private func startConnection(_ connectionInfo: (blockId: UUID, portName: String, isOutput: Bool)) {
        activeConnection = PendingConnection(
            sourceBlockId: connectionInfo.blockId,
            sourcePort: connectionInfo.portName,
            isOutput: connectionInfo.isOutput
        )
        isConnecting = true
    }

    private func completeConnection(_ success: Bool) {
        activeConnection = nil
        isConnecting = false
        connectionPreviewPath = nil
    }

    func updateConnectionPreview(to point: CGPoint) {
        guard let connection = activeConnection else { return }

        Task {
            let configuration: BlockConfiguration = await blockManager.getCurrentConfiguration()
            guard let sourceBlock = configuration.blocks.first(where: { $0.id == connection.sourceBlockId }) else { return }

            let startPoint: CGPoint = calculatePortPosition(
                block: sourceBlock,
                portName: connection.sourcePort,
                isOutput: connection.isOutput
            )

            connectionPreviewPath = createConnectionPath(from: startPoint, to: point)
        }
    }

    private func calculatePortPosition(block: SignalBlock, portName: String, isOutput: Bool) -> CGPoint {
        let blockWidth: CGFloat = 120
        let portSpacing: CGFloat = 20

        let ports: [String] = isOutput ? block.outputPortNames : block.inputPortNames
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

    private func createConnectionPath(from startPoint: CGPoint, to endPoint: CGPoint) -> CGPath {
        let path: CGMutablePath = CGMutablePath()
        path.move(to: startPoint)

        let controlPoint1: CGPoint = CGPoint(x: startPoint.x + 50, y: startPoint.y)
        let controlPoint2: CGPoint = CGPoint(x: endPoint.x - 50, y: endPoint.y)

        path.addCurve(to: endPoint, control1: controlPoint1, control2: controlPoint2)
        return path
    }

    // MARK: - Grid and Snapping

    func snapToGridIfEnabled(_ point: CGPoint) -> CGPoint {
        guard snapToGrid else { return point }

        let snappedX: CGFloat = round(point.x / gridSize) * gridSize
        let snappedY: CGFloat = round(point.y / gridSize) * gridSize

        return CGPoint(x: snappedX, y: snappedY)
    }

    func toggleGrid() {
        showingGrid.toggle()
        recordAction(.gridToggled(showingGrid))
    }

    func toggleSnapToGrid() {
        snapToGrid.toggle()
        recordAction(.snapToggled(snapToGrid))
    }

    // MARK: - Canvas Tools

    func setTool(_ tool: CanvasTool) {
        currentTool = tool
        recordAction(.toolChanged(tool))
    }

    // MARK: - Coordinate Conversion

    func canvasPointToScreen(_ point: CGPoint) -> CGPoint {
        return CGPoint(
            x: point.x * canvasScale + canvasOffset.width,
            y: point.y * canvasScale + canvasOffset.height
        )
    }

    func screenPointToCanvas(_ point: CGPoint) -> CGPoint {
        return CGPoint(
            x: (point.x - canvasOffset.width) / canvasScale,
            y: (point.y - canvasOffset.height) / canvasScale
        )
    }

    // MARK: - Undo/Redo

    private func recordAction(_ action: CanvasAction) {
        actionHistory.append(action)
        redoStack.removeAll()

        // Limit history size
        if actionHistory.count > 100 {
            actionHistory.removeFirst()
        }
    }

    func undo() {
        guard let lastAction = actionHistory.popLast() else { return }

        reverseAction(lastAction)
        redoStack.append(lastAction)
    }

    func redo() {
        guard let actionToRedo = redoStack.popLast() else { return }

        executeAction(actionToRedo)
        actionHistory.append(actionToRedo)
    }

    private func reverseAction(_ action: CanvasAction) {
        switch action {
        case .blockSelection(let selection):
            // This would need to restore previous selection
            break
        case .canvasPan(let from, _):
            canvasOffset = from
        case .canvasZoom(let from, _):
            canvasScale = from
        case .canvasReset, .gridToggled, .snapToggled, .toolChanged:
            // These would need specific reverse logic
            break
        case .blocksDeleted, .blocksDuplicated:
            // These would need to recreate/remove blocks
            break
        }
    }

    private func executeAction(_ action: CanvasAction) {
        switch action {
        case .blockSelection(let selection):
            selectedBlocks = selection
        case .canvasPan(_, let destination):
            canvasOffset = destination
        case .canvasZoom(_, let destination):
            canvasScale = destination
        case .canvasReset:
            resetCanvasView()
        case .gridToggled(let enabled):
            showingGrid = enabled
        case .snapToggled(let enabled):
            snapToGrid = enabled
        case .toolChanged(let tool):
            currentTool = tool
        case .blocksDeleted, .blocksDuplicated:
            // These would need specific execution logic
            break
        }
    }
}

// MARK: - Supporting Types

struct PendingConnection {
    let sourceBlockId: UUID
    let sourcePort: String
    let isOutput: Bool
}

struct PortReference {
    let blockId: UUID
    let portName: String
    let isOutput: Bool
}

enum CanvasTool: String, CaseIterable {
    case select
    case pan
    case zoom
    case connect

    var icon: String {
        switch self {
        case .select: return "cursorarrow"
        case .pan: return "hand.draw"
        case .zoom: return "magnifyingglass"
        case .connect: return "link"
        }
    }

    var displayName: String {
        switch self {
        case .select: return "Select"
        case .pan: return "Pan"
        case .zoom: return "Zoom"
        case .connect: return "Connect"
        }
    }
}

enum MinimapPosition: String, CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

enum CanvasAction {
    case blockSelection(Set<UUID>)
    case canvasPan(from: CGSize, destination: CGSize)
    case canvasZoom(from: CGFloat, destination: CGFloat)
    case canvasReset
    case gridToggled(Bool)
    case snapToggled(Bool)
    case toolChanged(CanvasTool)
    case blocksDeleted([UUID])
    case blocksDuplicated([UUID], [UUID]) // original, duplicated
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let blockCreated: Notification.Name = Notification.Name("blockCreated")
    static let blockRemoved: Notification.Name = Notification.Name("blockRemoved")
    static let blockMoved: Notification.Name = Notification.Name("blockMoved")
    static let blockParameterUpdated: Notification.Name = Notification.Name("blockParameterUpdated")
    static let connectionCreated: Notification.Name = Notification.Name("connectionCreated")
    static let connectionRemoved: Notification.Name = Notification.Name("connectionRemoved")
}
