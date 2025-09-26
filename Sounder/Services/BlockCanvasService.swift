import SwiftUI
import Foundation
import Combine

/// Service contract for managing the visual block canvas interface
public protocol BlockCanvasService {
    // MARK: - Event Publishers
    var selectionChanged: AnyPublisher<SignalBlock?, Never> { get }
    var connectionStarted: AnyPublisher<Connection, Never> { get }
    var connectionCompleted: AnyPublisher<Bool, Never> { get }

    // MARK: - Canvas Management
    func getCanvasState() async -> CanvasState
    func setZoomLevel(_ zoomLevel: Double) async
    func setViewportCenter(_ center: CGPoint) async
    func fitAllBlocks() async

    // MARK: - Block Visual Management
    func getBlockVisualProperties(for blockId: UUID) async throws -> BlockVisualProperties
    func setSelectedBlocks(_ selectedBlockIds: Set<UUID>) async
    func getSelectedBlocks() async -> Set<UUID>
    func highlightBlocks(matching searchTerm: String) async

    // MARK: - Drag and Drop Operations
    func beginBlockDrag(blockType: BlockType, dragInfo: Any) async -> UUID
    func updateDragPosition(dragSessionId: UUID, position: CGPoint) async
    func completeDrop(dragSessionId: UUID, at position: CGPoint) async throws -> SignalBlock?
    func cancelDrag(dragSessionId: UUID) async

    // MARK: - Connection Visual Management
    func beginConnectionDraw(from blockId: UUID, port portName: String, at startPosition: CGPoint) async -> UUID
    func updateConnectionDraw(connectionSessionId: UUID, to currentPosition: CGPoint) async
    func completeConnectionDraw(connectionSessionId: UUID, to targetBlockId: UUID?, port targetPortName: String?) async throws -> Connection?
    func cancelConnectionDraw(connectionSessionId: UUID) async

    // MARK: - Visual Feedback
    func showDropZones(for blockType: BlockType) async
    func hideDropZones() async
    func showConnectionFeedback(from sourceBlockId: UUID, port sourcePort: String) async
    func hideConnectionFeedback() async
    func setSignalFlowAnimation(_ isAnimating: Bool) async

    // MARK: - Context Menu Operations
    func getBlockContextMenuItems(for blockId: UUID) async -> [ContextMenuItem]
    func getConnectionContextMenuItems(for connectionId: UUID) async -> [ContextMenuItem]
    func getCanvasContextMenuItems(at position: CGPoint) async -> [ContextMenuItem]
}

/// Concrete implementation of BlockCanvasService
@MainActor
public class BlockCanvasServiceImpl: BlockCanvasService, ObservableObject {
    @Published public var canvasState = CanvasState(
        size: CGSize(width: 2000, height: 1500),
        zoomLevel: 1.0,
        viewportCenter: CGPoint(x: 1000, y: 750),
        viewportSize: CGSize(width: 800, height: 600)
    )

    @Published public var selectedBlocks: Set<UUID> = []
    @Published public var highlightedBlocks: Set<UUID> = []
    @Published public var showingDropZones = false
    @Published public var showingConnectionFeedback = false
    @Published public var isSignalFlowAnimating = false

    // Event publishers
    private let selectionChangedSubject = PassthroughSubject<SignalBlock?, Never>()
    private let connectionStartedSubject = PassthroughSubject<Connection, Never>()
    private let connectionCompletedSubject = PassthroughSubject<Bool, Never>()

    public var selectionChanged: AnyPublisher<SignalBlock?, Never> {
        selectionChangedSubject.eraseToAnyPublisher()
    }

    public var connectionStarted: AnyPublisher<Connection, Never> {
        connectionStartedSubject.eraseToAnyPublisher()
    }

    public var connectionCompleted: AnyPublisher<Bool, Never> {
        connectionCompletedSubject.eraseToAnyPublisher()
    }

    private var dragSessions: [UUID: DragSession] = [:]
    private var connectionSessions: [UUID: ConnectionSession] = [:]

    private let blockManagerService: BlockManagerService
    private let eventPublisher = PassthroughSubject<BlockCanvasEvent, Never>()

    public init(blockManagerService: BlockManagerService) {
        self.blockManagerService = blockManagerService
    }

    // MARK: - Canvas Management

    public func getCanvasState() async -> CanvasState {
        return canvasState
    }

    public func setZoomLevel(_ zoomLevel: Double) async {
        let clampedZoom = max(0.1, min(5.0, zoomLevel))
        canvasState = CanvasState(
            size: canvasState.size,
            zoomLevel: clampedZoom,
            viewportCenter: canvasState.viewportCenter,
            viewportSize: canvasState.viewportSize
        )

        eventPublisher.send(.canvasStateChanged(canvasState))
    }

    public func setViewportCenter(_ center: CGPoint) async {
        canvasState = CanvasState(
            size: canvasState.size,
            zoomLevel: canvasState.zoomLevel,
            viewportCenter: center,
            viewportSize: canvasState.viewportSize
        )

        eventPublisher.send(.canvasStateChanged(canvasState))
    }

    public func fitAllBlocks() async {
        let config = await blockManagerService.getCurrentConfiguration()
        guard !config.blocks.isEmpty else { return }

        // Calculate bounding box of all blocks
        let positions = config.blocks.map { $0.position }
        let minX = positions.map { $0.x }.min() ?? 0
        let maxX = positions.map { $0.x }.max() ?? 0
        let minY = positions.map { $0.y }.min() ?? 0
        let maxY = positions.map { $0.y }.max() ?? 0

        let blocksWidth = maxX - minX + 200 // Add padding
        let blocksHeight = maxY - minY + 200

        // Calculate zoom to fit all blocks
        let zoomX = canvasState.viewportSize.width / blocksWidth
        let zoomY = canvasState.viewportSize.height / blocksHeight
        let fitZoom = min(zoomX, zoomY, 2.0) // Cap at 2x zoom

        // Center on blocks
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2

        canvasState = CanvasState(
            size: canvasState.size,
            zoomLevel: fitZoom,
            viewportCenter: CGPoint(x: centerX, y: centerY),
            viewportSize: canvasState.viewportSize
        )

        eventPublisher.send(.canvasStateChanged(canvasState))
    }

    // MARK: - Block Visual Management

    public func getBlockVisualProperties(for blockId: UUID) async throws -> BlockVisualProperties {
        let config = await blockManagerService.getCurrentConfiguration()
        guard let block = config.blocks.first(where: { $0.id == blockId }) else {
            throw BlockCanvasError.blockNotFoundError(blockId)
        }

        let isSelected = selectedBlocks.contains(blockId)
        let isHighlighted = highlightedBlocks.contains(blockId)

        // Determine colors based on block type
        let baseColor = colorForBlockType(block.type)
        let borderColor = isSelected ? Color.blue : (isHighlighted ? Color.yellow : Color.gray)

        return BlockVisualProperties(
            size: block.visualSize,
            color: baseColor,
            borderColor: borderColor,
            borderWidth: isSelected ? 3.0 : (isHighlighted ? 2.0 : 1.0),
            cornerRadius: 8.0,
            shadowOpacity: isSelected ? 0.4 : 0.2,
            isHighlighted: isHighlighted,
            isSelected: isSelected
        )
    }

    public func setSelectedBlocks(_ selectedBlockIds: Set<UUID>) async {
        selectedBlocks = selectedBlockIds
        eventPublisher.send(.blockSelectionChanged(selectedBlocks))

        if let firstSelected = selectedBlockIds.first {
            let configuration = await blockManagerService.getCurrentConfiguration()
            if let selectedBlock = configuration.blocks.first(where: { $0.id == firstSelected }) {
                selectionChangedSubject.send(selectedBlock)
            } else {
                selectionChangedSubject.send(nil)
            }
        } else {
            selectionChangedSubject.send(nil)
        }
    }

    public func getSelectedBlocks() async -> Set<UUID> {
        return selectedBlocks
    }

    public func highlightBlocks(matching searchTerm: String) async {
        let config = await blockManagerService.getCurrentConfiguration()
        let term = searchTerm.lowercased()

        highlightedBlocks = Set(config.blocks.compactMap { block in
            if block.title.lowercased().contains(term) ||
               block.type.displayName.lowercased().contains(term) ||
               block.type.rawValue.contains(term) {
                return block.id
            }
            return nil
        })
    }

    // MARK: - Drag and Drop Operations

    public func beginBlockDrag(blockType: BlockType, dragInfo: Any) async -> UUID {
        let sessionId = UUID()
        let session = DragSession(
            id: sessionId,
            blockType: blockType,
            startTime: Date(),
            currentPosition: .zero
        )

        dragSessions[sessionId] = session
        showingDropZones = true

        eventPublisher.send(.blockDragStarted(blockType, sessionId))
        return sessionId
    }

    public func updateDragPosition(dragSessionId: UUID, position: CGPoint) async {
        guard var session = dragSessions[dragSessionId] else { return }

        session.currentPosition = position
        dragSessions[dragSessionId] = session
    }

    public func completeDrop(dragSessionId: UUID, at position: CGPoint) async throws -> SignalBlock? {
        guard let session = dragSessions[dragSessionId] else {
            throw BlockCanvasError.dragSessionNotFoundError(dragSessionId)
        }

        // Validate drop position
        guard position.x >= 0 && position.y >= 0 &&
              position.x <= canvasState.size.width &&
              position.y <= canvasState.size.height else {
            throw BlockCanvasError.invalidDropLocationError(position)
        }

        // Create the block
        let block = try await blockManagerService.createBlock(type: session.blockType, at: position)

        // Clean up
        dragSessions.removeValue(forKey: dragSessionId)
        showingDropZones = false

        eventPublisher.send(.blockDragCompleted(dragSessionId, position))
        return block
    }

    public func cancelDrag(dragSessionId: UUID) async {
        dragSessions.removeValue(forKey: dragSessionId)
        showingDropZones = false
        eventPublisher.send(.blockDragCancelled(dragSessionId))
    }

    // MARK: - Connection Visual Management

    public func beginConnectionDraw(from blockId: UUID, port portName: String, at startPosition: CGPoint) async -> UUID {
        let sessionId = UUID()
        let session = ConnectionSession(
            id: sessionId,
            sourceBlockId: blockId,
            sourcePort: portName,
            startPosition: startPosition,
            currentPosition: startPosition
        )

        connectionSessions[sessionId] = session
        showingConnectionFeedback = true

        eventPublisher.send(.connectionDrawStarted(blockId, portName, sessionId))
        return sessionId
    }

    public func updateConnectionDraw(connectionSessionId: UUID, to currentPosition: CGPoint) async {
        guard var session = connectionSessions[connectionSessionId] else { return }

        session.currentPosition = currentPosition
        connectionSessions[connectionSessionId] = session
    }

    public func completeConnectionDraw(
        connectionSessionId: UUID,
        to targetBlockId: UUID?,
        port targetPortName: String?
    ) async throws -> Connection? {
        guard let session = connectionSessions[connectionSessionId] else {
            throw BlockCanvasError.connectionSessionNotFoundError(connectionSessionId)
        }

        var connection: Connection?

        if let targetBlockId = targetBlockId, let targetPortName = targetPortName {
            // Validate connection before creating
            let isValid = await blockManagerService.validateConnection(
                from: session.sourceBlockId, sourcePort: session.sourcePort,
                to: targetBlockId, destinationPort: targetPortName
            )

            if isValid {
                connection = try await blockManagerService.createConnection(
                    from: session.sourceBlockId, sourcePort: session.sourcePort,
                    to: targetBlockId, destinationPort: targetPortName
                )
            }
        }

        // Clean up
        connectionSessions.removeValue(forKey: connectionSessionId)
        showingConnectionFeedback = false

        eventPublisher.send(.connectionDrawCompleted(connectionSessionId))
        return connection
    }

    public func cancelConnectionDraw(connectionSessionId: UUID) async {
        connectionSessions.removeValue(forKey: connectionSessionId)
        showingConnectionFeedback = false
        eventPublisher.send(.connectionDrawCancelled(connectionSessionId))
    }

    // MARK: - Visual Feedback

    public func showDropZones(for blockType: BlockType) async {
        showingDropZones = true
    }

    public func hideDropZones() async {
        showingDropZones = false
    }

    public func showConnectionFeedback(from sourceBlockId: UUID, port sourcePort: String) async {
        showingConnectionFeedback = true
    }

    public func hideConnectionFeedback() async {
        showingConnectionFeedback = false
    }

    public func setSignalFlowAnimation(_ isAnimating: Bool) async {
        isSignalFlowAnimating = isAnimating
    }

    // MARK: - Context Menu Operations

    public func getBlockContextMenuItems(for blockId: UUID) async -> [ContextMenuItem] {
        return [
            ContextMenuItem(
                id: "duplicate",
                title: "Duplicate",
                icon: "doc.on.doc",
                isEnabled: true,
                action: { /* Duplicate block logic */ }
            ),
            ContextMenuItem(
                id: "delete",
                title: "Delete",
                icon: "trash",
                isEnabled: true,
                action: { /* Delete block logic */ }
            ),
            ContextMenuItem(
                id: "copy",
                title: "Copy",
                icon: "doc.on.clipboard",
                isEnabled: true,
                action: { /* Copy block logic */ }
            )
        ]
    }

    public func getConnectionContextMenuItems(for connectionId: UUID) async -> [ContextMenuItem] {
        return [
            ContextMenuItem(
                id: "delete",
                title: "Remove Connection",
                icon: "trash",
                isEnabled: true,
                action: { /* Remove connection logic */ }
            ),
            ContextMenuItem(
                id: "bypass",
                title: "Bypass Connection",
                icon: "minus.circle",
                isEnabled: true,
                action: { /* Bypass connection logic */ }
            )
        ]
    }

    public func getCanvasContextMenuItems(at position: CGPoint) async -> [ContextMenuItem] {
        return [
            ContextMenuItem(
                id: "paste",
                title: "Paste",
                icon: "doc.on.clipboard.fill",
                isEnabled: true, // Would check clipboard
                action: { /* Paste logic */ }
            ),
            ContextMenuItem(
                id: "selectAll",
                title: "Select All",
                icon: "selection.pin.in.out",
                isEnabled: true,
                action: { /* Select all blocks */ }
            ),
            ContextMenuItem(
                id: "fitAll",
                title: "Fit All Blocks",
                icon: "arrow.up.left.and.arrow.down.right",
                isEnabled: true,
                action: { /* Fit all blocks */ }
            )
        ]
    }

    // MARK: - Private Methods

    private func colorForBlockType(_ blockType: BlockType) -> Color {
        switch blockType.category {
        case .generators:
            return Color.green.opacity(0.7)
        case .modulation:
            return Color.orange.opacity(0.7)
        case .processing:
            return Color.blue.opacity(0.7)
        case .analysis:
            return Color.purple.opacity(0.7)
        case .output:
            return Color.red.opacity(0.7)
        }
    }

    // MARK: - Event Publishing

    public var events: AnyPublisher<BlockCanvasEvent, Never> {
        eventPublisher.eraseToAnyPublisher()
    }
}

// MARK: - Data Types

public struct CanvasState {
    public let size: CGSize
    public let zoomLevel: Double
    public let viewportCenter: CGPoint
    public let viewportSize: CGSize
}

public struct BlockVisualProperties {
    public let size: CGSize
    public let color: Color
    public let borderColor: Color
    public let borderWidth: Double
    public let cornerRadius: Double
    public let shadowOpacity: Double
    public let isHighlighted: Bool
    public let isSelected: Bool
}

public struct ContextMenuItem {
    public let id: String
    public let title: String
    public let icon: String?
    public let isEnabled: Bool
    public let action: () -> Void

    public init(id: String, title: String, icon: String?, isEnabled: Bool, action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.icon = icon
        self.isEnabled = isEnabled
        self.action = action
    }
}

// MARK: - Session Types

private struct DragSession {
    let id: UUID
    let blockType: BlockType
    let startTime: Date
    var currentPosition: CGPoint
}

private struct ConnectionSession {
    let id: UUID
    let sourceBlockId: UUID
    let sourcePort: String
    let startPosition: CGPoint
    var currentPosition: CGPoint
}

// MARK: - Error Types

public enum BlockCanvasError: Error, LocalizedError {
    case blockNotFoundError(UUID)
    case invalidDropLocationError(CGPoint)
    case invalidConnectionError(String)
    case dragSessionNotFoundError(UUID)
    case connectionSessionNotFoundError(UUID)

    public var errorDescription: String? {
        switch self {
        case .blockNotFoundError(let id):
            return "Block not found: \(id)"
        case .invalidDropLocationError(let position):
            return "Invalid drop location: \(position)"
        case .invalidConnectionError(let message):
            return "Invalid connection: \(message)"
        case .dragSessionNotFoundError(let id):
            return "Drag session not found: \(id)"
        case .connectionSessionNotFoundError(let id):
            return "Connection session not found: \(id)"
        }
    }
}

// MARK: - Event Types

/// Events published by the BlockCanvasService
public enum BlockCanvasEvent {
    case canvasStateChanged(CanvasState)
    case blockSelectionChanged(Set<UUID>)
    case blockDragStarted(BlockType, UUID)
    case blockDragCompleted(UUID, CGPoint)
    case blockDragCancelled(UUID)
    case connectionDrawStarted(UUID, String, UUID)
    case connectionDrawCompleted(UUID)
    case connectionDrawCancelled(UUID)
    case contextMenuRequested(CGPoint)
}
