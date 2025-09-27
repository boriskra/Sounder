import SwiftUI
import Foundation
import Combine

/// Service contract for managing the visual block canvas interface
/// Provides read/write access to the block canvas surface and its interactions.
public protocol BlockCanvasService {
    // MARK: - Event Publishers
    /// Emits when the selected block changes, providing the new selection or `nil` if nothing is selected.
    /// Emits when the selected block changes, providing the new selection or `nil` if nothing is selected.
    var selectionChanged: AnyPublisher<SignalBlock?, Never> { get }
    /// Emits when the user begins drawing a connection, providing the originating connection metadata.
    /// Emits when the user begins drawing a connection, providing the originating connection metadata.
    var connectionStarted: AnyPublisher<Connection, Never> { get }
    /// Emits a Boolean describing whether the connection gesture completed successfully.
    /// Emits a Boolean describing whether the connection gesture completed successfully.
    var connectionCompleted: AnyPublisher<Bool, Never> { get }

    // MARK: - Canvas Management
    /// Returns the current canvas state, including zoom and viewport information.
    /// Returns the current canvas state, including zoom and viewport information.
    func getCanvasState() async -> CanvasState
    /// Updates the zoom level used to render the canvas.
    /// Updates the zoom level used to render the canvas.
    func setZoomLevel(_ zoomLevel: Double) async
    /// Updates the viewport center so the canvas scroll position changes.
    /// Updates the viewport center so the canvas scroll position changes.
    func setViewportCenter(_ center: CGPoint) async
    /// Adjusts the viewport and zoom to fit every block currently on the canvas.
    /// Adjusts the viewport and zoom to fit every block currently on the canvas.
    func fitAllBlocks() async

    // MARK: - Block Visual Management
    /// Returns visual styling information for a given block identifier.
    /// Returns visual styling information for a given block identifier.
    func getBlockVisualProperties(for blockId: UUID) async throws -> BlockVisualProperties
    /// Updates the selection to the supplied block identifiers.
    /// Updates the selection to the supplied block identifiers.
    func setSelectedBlocks(_ selectedBlockIds: Set<UUID>) async
    /// Returns the current set of selected block identifiers.
    /// Returns the current set of selected block identifiers.
    func getSelectedBlocks() async -> Set<UUID>
    /// Highlights blocks whose metadata matches the provided search term.
    /// Highlights blocks whose metadata matches the provided search term.
    func highlightBlocks(matching searchTerm: String) async

    // MARK: - Drag and Drop Operations
    /// Begins a block drag session for the supplied block type and returns the session identifier.
    /// Begins a block drag session for the supplied block type and returns the session identifier.
    func beginBlockDrag(blockType: BlockType, dragInfo: Any) async -> UUID
    /// Updates a block drag session with its latest pointer position.
    /// Updates a block drag session with its latest pointer position.
    func updateDragPosition(dragSessionId: UUID, position: CGPoint) async
    /// Completes a drag session by attempting to drop at the provided position and returns the created block, if any.
    /// Completes a drag session by attempting to drop at the provided position and returns the created block, if any.
    func completeDrop(dragSessionId: UUID, at position: CGPoint) async throws -> SignalBlock?
    /// Cancels the current drag session, removing any temporary state.
    /// Cancels the current drag session, removing any temporary state.
    func cancelDrag(dragSessionId: UUID) async

    // MARK: - Connection Visual Management
    /// Starts a new connection drawing session originating from the given block and port.
    /// Starts a new connection drawing session originating from the given block and port.
    func beginConnectionDraw(from blockId: UUID, port portName: String, at startPosition: CGPoint) async -> UUID
    /// Updates the temporary connection line to the latest cursor position.
    /// Updates the temporary connection line to the latest cursor position.
    func updateConnectionDraw(connectionSessionId: UUID, to currentPosition: CGPoint) async
    /// Attempts to finish drawing the connection, returning the created connection if the link is valid.
    /// Attempts to finish drawing the connection, returning the created connection if the link is valid.
    func completeConnectionDraw(connectionSessionId: UUID, to targetBlockId: UUID?, port targetPortName: String?) async throws -> Connection?
    /// Cancels the connection drawing interaction and removes transient visuals.
    /// Cancels the connection drawing interaction and removes transient visuals.
    func cancelConnectionDraw(connectionSessionId: UUID) async

    // MARK: - Visual Feedback
    /// Displays drop zone affordances for the provided block type.
    /// Displays drop zone affordances for the provided block type.
    func showDropZones(for blockType: BlockType) async
    /// Hides any block drop zones currently rendered.
    /// Hides any block drop zones currently rendered.
    func hideDropZones() async
    /// Shows visual feedback for a connection originating from the specified source.
    /// Shows visual feedback for a connection originating from the specified source.
    func showConnectionFeedback(from sourceBlockId: UUID, port sourcePort: String) async
    /// Hides the current connection feedback overlay.
    /// Hides the current connection feedback overlay.
    func hideConnectionFeedback() async
    /// Enables or disables the animated signal flow overlay.
    /// Enables or disables the animated signal flow overlay.
    func setSignalFlowAnimation(_ isAnimating: Bool) async

    // MARK: - Context Menu Operations
    /// Provides context menu items that apply to a specific block.
    /// Provides context menu items that apply to a specific block.
    func getBlockContextMenuItems(for blockId: UUID) async -> [ContextMenuItem]
    /// Provides context menu items that apply to a specific connection.
    /// Provides context menu items that apply to a specific connection.
    func getConnectionContextMenuItems(for connectionId: UUID) async -> [ContextMenuItem]
    /// Provides context menu items that apply to the canvas at the given point.
    /// Provides context menu items that apply to the canvas at the given point.
    func getCanvasContextMenuItems(at position: CGPoint) async -> [ContextMenuItem]
}

/// Concrete implementation of BlockCanvasService
@MainActor
/// Default `BlockCanvasService` implementation that coordinates canvas rendering and user interactions.
public class BlockCanvasServiceImpl: BlockCanvasService, ObservableObject {
    /// State representing the current canvas viewport and zoom configuration.
    @Published public var canvasState: CanvasState = CanvasState(
        size: CGSize(width: 2000, height: 1500),
        zoomLevel: 1.0,
        viewportCenter: CGPoint(x: 1000, y: 750),
        viewportSize: CGSize(width: 800, height: 600)
    )

    /// Identifiers of currently selected blocks on the canvas.
    @Published public var selectedBlocks: Set<UUID> = []
    /// Identifiers of blocks that match the most recent highlight request.
    @Published public var highlightedBlocks: Set<UUID> = []
    /// Indicates whether drop zone affordances are visible.
    @Published public var showingDropZones: Bool = false
    /// Indicates whether connection feedback visuals are presented.
    @Published public var showingConnectionFeedback: Bool = false
    /// Indicates whether the signal flow animation is active.
    @Published public var isSignalFlowAnimating: Bool = false

    // Event publishers
    private let selectionChangedSubject: PassthroughSubject<SignalBlock?, Never> = PassthroughSubject<SignalBlock?, Never>()
    private let connectionStartedSubject: PassthroughSubject<Connection, Never> = PassthroughSubject<Connection, Never>()
    private let connectionCompletedSubject: PassthroughSubject<Bool, Never> = PassthroughSubject<Bool, Never>()

    /// Publisher for block selection changes originating from this service.
    public var selectionChanged: AnyPublisher<SignalBlock?, Never> {
        selectionChangedSubject.eraseToAnyPublisher()
    }

    /// Publisher for new connection drawing sessions.
    public var connectionStarted: AnyPublisher<Connection, Never> {
        connectionStartedSubject.eraseToAnyPublisher()
    }

    /// Publisher that reports whether a connection draw concluded successfully.
    public var connectionCompleted: AnyPublisher<Bool, Never> {
        connectionCompletedSubject.eraseToAnyPublisher()
    }

    private var dragSessions: [UUID: DragSession] = [UUID: DragSession]()
    private var connectionSessions: [UUID: ConnectionSession] = [UUID: ConnectionSession]()

    private let blockManagerService: BlockManagerService
    private let eventPublisher: PassthroughSubject<BlockCanvasEvent, Never> = PassthroughSubject<BlockCanvasEvent, Never>()

    /// Creates a new service instance backed by the provided block manager.
    public init(blockManagerService: BlockManagerService) {
        self.blockManagerService = blockManagerService
    }

    // MARK: - Canvas Management

    /// Returns the current canvas state snapshot.
    public func getCanvasState() async -> CanvasState {
        return canvasState
    }

    /// Adjusts the canvas zoom level, clamping to supported bounds.
    public func setZoomLevel(_ zoomLevel: Double) async {
        let clampedZoom: Double = max(0.1, min(5.0, zoomLevel))
        canvasState = CanvasState(
            size: canvasState.size,
            zoomLevel: clampedZoom,
            viewportCenter: canvasState.viewportCenter,
            viewportSize: canvasState.viewportSize
        )

        eventPublisher.send(.canvasStateChanged(canvasState))
    }

    /// Updates the canvas viewport center point.
    public func setViewportCenter(_ center: CGPoint) async {
        canvasState = CanvasState(
            size: canvasState.size,
            zoomLevel: canvasState.zoomLevel,
            viewportCenter: center,
            viewportSize: canvasState.viewportSize
        )

        eventPublisher.send(.canvasStateChanged(canvasState))
    }

    /// Zooms and pans the viewport so all blocks fit inside the visible area.
    public func fitAllBlocks() async {
        let config: BlockConfiguration = await blockManagerService.getCurrentConfiguration()
        guard !config.blocks.isEmpty else { return }

        // Calculate bounding box of all blocks
        let positions: [CGPoint] = config.blocks.map { $0.position }
        let minX: CGFloat = positions.map { $0.x }.min() ?? 0
        let maxX: CGFloat = positions.map { $0.x }.max() ?? 0
        let minY: CGFloat = positions.map { $0.y }.min() ?? 0
        let maxY: CGFloat = positions.map { $0.y }.max() ?? 0

        let blocksWidth: CGFloat = maxX - minX + 200 // Add padding
        let blocksHeight: CGFloat = maxY - minY + 200

        // Calculate zoom to fit all blocks
        let zoomX: CGFloat = canvasState.viewportSize.width / blocksWidth
        let zoomY: CGFloat = canvasState.viewportSize.height / blocksHeight
        let fitZoom: Double = min(zoomX, zoomY, 2.0) // Cap at 2x zoom

        // Center on blocks
        let centerX: CGFloat = (minX + maxX) / 2
        let centerY: CGFloat = (minY + maxY) / 2

        canvasState = CanvasState(
            size: canvasState.size,
            zoomLevel: fitZoom,
            viewportCenter: CGPoint(x: centerX, y: centerY),
            viewportSize: canvasState.viewportSize
        )

        eventPublisher.send(.canvasStateChanged(canvasState))
    }

    // MARK: - Block Visual Management

    /// Retrieves styling metadata used to render the specified block.
    public func getBlockVisualProperties(for blockId: UUID) async throws -> BlockVisualProperties {
        let config: BlockConfiguration = await blockManagerService.getCurrentConfiguration()
        guard let block = config.blocks.first(where: { $0.id == blockId }) else {
            throw BlockCanvasError.blockNotFoundError(blockId)
        }

        let isSelected: Bool = selectedBlocks.contains(blockId)
        let isHighlighted: Bool = highlightedBlocks.contains(blockId)

        // Determine colors based on block type
        let baseColor: Color = colorForBlockType(block.type)
        let borderColor: Color = isSelected ? Color.blue : (isHighlighted ? Color.yellow : Color.gray)

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

    /// Updates the currently selected blocks, broadcasting selection changes.
    public func setSelectedBlocks(_ selectedBlockIds: Set<UUID>) async {
        selectedBlocks = selectedBlockIds
        eventPublisher.send(.blockSelectionChanged(selectedBlocks))

        if let firstSelected = selectedBlockIds.first {
            let configuration: BlockConfiguration = await blockManagerService.getCurrentConfiguration()
            if let selectedBlock = configuration.blocks.first(where: { $0.id == firstSelected }) {
                selectionChangedSubject.send(selectedBlock)
            } else {
                selectionChangedSubject.send(nil)
            }
        } else {
            selectionChangedSubject.send(nil)
        }
    }

    /// Returns the set of selected block identifiers.
    public func getSelectedBlocks() async -> Set<UUID> {
        return selectedBlocks
    }

    /// Highlights blocks whose metadata contains the provided search term.
    public func highlightBlocks(matching searchTerm: String) async {
        let config: BlockConfiguration = await blockManagerService.getCurrentConfiguration()
        let term: String = searchTerm.lowercased()

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

    /// Starts tracking a block drag interaction and returns the drag session identifier.
    public func beginBlockDrag(blockType: BlockType, dragInfo: Any) async -> UUID {
        let sessionId: UUID = UUID()
        let session: DragSession = DragSession(
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

    /// Updates the active drag session with the most recent cursor position.
    public func updateDragPosition(dragSessionId: UUID, position: CGPoint) async {
        guard var session = dragSessions[dragSessionId] else { return }

        session.currentPosition = position
        dragSessions[dragSessionId] = session
    }

    /// Attempts to finish a drag session by dropping a block at the provided position.
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
        let block: SignalBlock = try await blockManagerService.createBlock(type: session.blockType, at: position)

        // Clean up
        dragSessions.removeValue(forKey: dragSessionId)
        showingDropZones = false

        eventPublisher.send(.blockDragCompleted(dragSessionId, position))
        return block
    }

    /// Cancels the specified drag session and clears temporary state.
    public func cancelDrag(dragSessionId: UUID) async {
        dragSessions.removeValue(forKey: dragSessionId)
        showingDropZones = false
        eventPublisher.send(.blockDragCancelled(dragSessionId))
    }

    // MARK: - Connection Visual Management

    /// Begins a connection drawing session originating from the supplied block and port.
    public func beginConnectionDraw(from blockId: UUID, port portName: String, at startPosition: CGPoint) async -> UUID {
        let sessionId: UUID = UUID()
        let session: ConnectionSession = ConnectionSession(
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

    /// Updates the in-progress connection draw with the latest cursor position.
    public func updateConnectionDraw(connectionSessionId: UUID, to currentPosition: CGPoint) async {
        guard var session = connectionSessions[connectionSessionId] else { return }

        session.currentPosition = currentPosition
        connectionSessions[connectionSessionId] = session
    }

    /// Completes an in-progress connection draw and returns the created connection when successful.
    public func completeConnectionDraw(
        connectionSessionId: UUID,
        to targetBlockId: UUID?,
        port targetPortName: String?
    ) async throws -> Connection? {
        guard let session = connectionSessions[connectionSessionId] else {
            throw BlockCanvasError.connectionSessionNotFoundError(connectionSessionId)
        }

        var connection: Connection? = nil

        if let targetBlockId = targetBlockId, let targetPortName = targetPortName {
            // Validate connection before creating
            let isValid: Bool = await blockManagerService.validateConnection(
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

    /// Cancels the active connection drawing session.
    public func cancelConnectionDraw(connectionSessionId: UUID) async {
        connectionSessions.removeValue(forKey: connectionSessionId)
        showingConnectionFeedback = false
        eventPublisher.send(.connectionDrawCancelled(connectionSessionId))
    }

    // MARK: - Visual Feedback

    /// Displays drop zone affordances for the specified block type.
    public func showDropZones(for blockType: BlockType) async {
        showingDropZones = true
    }

    /// Hides any currently visible drop zone affordances.
    public func hideDropZones() async {
        showingDropZones = false
    }

    /// Shows feedback for a connection being drawn from the provided block and port.
    public func showConnectionFeedback(from sourceBlockId: UUID, port sourcePort: String) async {
        showingConnectionFeedback = true
    }

    /// Hides connection drawing feedback overlays.
    public func hideConnectionFeedback() async {
        showingConnectionFeedback = false
    }

    /// Toggles the animated signal flow overlay.
    public func setSignalFlowAnimation(_ isAnimating: Bool) async {
        isSignalFlowAnimating = isAnimating
    }

    // MARK: - Context Menu Operations

    /// Builds context menu actions relevant to the specified block.
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

    /// Builds context menu actions relevant to the specified connection.
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

    /// Builds context menu actions appropriate for the canvas at the given location.
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

    /// Publisher that exposes internal canvas events for observers.
    public var events: AnyPublisher<BlockCanvasEvent, Never> {
        eventPublisher.eraseToAnyPublisher()
    }
}

// MARK: - Data Types

/// Snapshot of canvas layout and viewport configuration.
public struct CanvasState {
    /// Total logical size of the canvas coordinate space.
    public let size: CGSize
    /// Current zoom level applied to the canvas.
    public let zoomLevel: Double
    /// Center point of the viewport in canvas coordinates.
    public let viewportCenter: CGPoint
    /// Visible viewport size in canvas coordinates.
    public let viewportSize: CGSize
}

/// Visual styling attributes for rendering a block.
public struct BlockVisualProperties {
    /// Size of the block in canvas coordinates.
    public let size: CGSize
    /// Fill color to use when presenting the block.
    public let color: Color
    /// Border color applied around the block.
    public let borderColor: Color
    /// Thickness of the border stroke.
    public let borderWidth: Double
    /// Corner radius applied to the block outline.
    public let cornerRadius: Double
    /// Opacity of the drop shadow appearing under the block.
    public let shadowOpacity: Double
    /// Indicates whether the block is highlighted.
    public let isHighlighted: Bool
    /// Indicates whether the block is currently selected.
    public let isSelected: Bool
}

/// Describes an item to surface in a context menu.
public struct ContextMenuItem {
    /// Unique identifier for the context menu item.
    public let id: String
    /// Display title shown to the user.
    public let title: String
    /// Optional system icon identifier associated with the action.
    public let icon: String?
    /// Indicates whether the item is currently enabled.
    public let isEnabled: Bool
    /// Closure executed when the item is selected.
    public let action: () -> Void

    /// Creates a new context menu item using the provided behavior closure.
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

/// Errors thrown while interacting with the block canvas.
public enum BlockCanvasError: Error, LocalizedError {
    /// A block matching the supplied identifier could not be located.
    case blockNotFoundError(UUID)
    /// The provided drop location falls outside the valid canvas area.
    case invalidDropLocationError(CGPoint)
    /// A requested connection failed validation for the supplied reason.
    case invalidConnectionError(String)
    /// A drag session identifier did not match an active session.
    case dragSessionNotFoundError(UUID)
    /// A connection session identifier did not match an active session.
    case connectionSessionNotFoundError(UUID)

    /// Textual description for presenting the error to users.
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
    /// Indicates that the canvas state changed.
    case canvasStateChanged(CanvasState)
    /// Indicates that the selected block identifiers changed.
    case blockSelectionChanged(Set<UUID>)
    /// Indicates a block drag interaction started.
    case blockDragStarted(BlockType, UUID)
    /// Indicates a block drag interaction finished at a location.
    case blockDragCompleted(UUID, CGPoint)
    /// Indicates a block drag interaction was cancelled.
    case blockDragCancelled(UUID)
    /// Indicates a connection drawing interaction started.
    case connectionDrawStarted(UUID, String, UUID)
    /// Indicates a connection drawing interaction finished.
    case connectionDrawCompleted(UUID)
    /// Indicates a connection drawing interaction was cancelled.
    case connectionDrawCancelled(UUID)
    /// Indicates that a context menu has been requested for the specified location.
    case contextMenuRequested(CGPoint)
}
