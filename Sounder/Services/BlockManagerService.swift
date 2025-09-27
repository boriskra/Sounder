import Foundation
import SwiftUI
import Combine

/// Service contract for managing signal processing blocks in the visual interface
public protocol BlockManagerService {
    // MARK: - Block Management
    func createBlock(type: BlockType, at position: CGPoint) async throws -> SignalBlock
    func removeBlock(id blockId: UUID) async throws
    func moveBlock(id blockId: UUID, to position: CGPoint) async throws
    func updateBlockParameter(blockId: UUID, parameterName: String, value: Double) async throws

    // MARK: - Connection Management
    func createConnection(from sourceBlockId: UUID, sourcePort: String, to destinationBlockId: UUID, destinationPort: String) async throws -> Connection
    func removeConnection(id connectionId: UUID) async throws
    func validateConnection(from sourceBlockId: UUID, sourcePort: String, to destinationBlockId: UUID, destinationPort: String) async -> Bool

    // MARK: - Configuration Management
    func getCurrentConfiguration() async -> BlockConfiguration
    func loadConfiguration(from url: URL) async throws -> BlockConfiguration
    func saveConfiguration(to url: URL) async throws
    func clearConfiguration() async

    // MARK: - Audio Engine Integration
    func startAudioProcessing() async throws
    func stopAudioProcessing() async
    func isAudioProcessing() async -> Bool
    func setOutputDevice(_ device: OutputDevice) async throws
}

/// Concrete implementation of BlockManagerService
@MainActor
public class BlockManagerServiceImpl: BlockManagerService, ObservableObject {
    @Published public var currentConfiguration = BlockConfiguration.empty()
    @Published public var isProcessing = false

    private let audioService: AudioBlockService
    private let eventPublisher = PassthroughSubject<BlockManagerEvent, Never>()

    // Additional publishers for UI binding
    private let blockUpdatedSubject = PassthroughSubject<SignalBlock, Never>()

    public var blockUpdated: AnyPublisher<SignalBlock, Never> {
        blockUpdatedSubject.eraseToAnyPublisher()
    }

    public init(audioService: AudioBlockService) {
        self.audioService = audioService
    }

    // MARK: - Block Management

    public func createBlock(type: BlockType, at position: CGPoint) async throws -> SignalBlock {
        // Create block with default parameters and ports
        let block = SignalBlock(
            type: type,
            title: type.displayName,
            position: position,
            parameters: type.createDefaultParameters(),
            inputPorts: type.defaultInputPorts,
            outputPorts: type.defaultOutputPorts
        )

        // Add to configuration
        currentConfiguration = try currentConfiguration.addingBlock(block)

        // Register with audio engine if processing
        if isProcessing {
            try await audioService.registerBlock(block)
        }

        eventPublisher.send(.blockCreated(block))
        return block
    }

    public func removeBlock(id blockId: UUID) async throws {
        // Verify block exists
        guard currentConfiguration.blocks.contains(where: { $0.id == blockId }) else {
            throw BlockManagerError.blockNotFoundError(blockId)
        }

        // Unregister from audio engine
        if isProcessing {
            await audioService.unregisterBlock(id: blockId)
        }

        // Remove from configuration (this also removes connections)
        currentConfiguration = try currentConfiguration.removingBlock(blockId)

        eventPublisher.send(.blockRemoved(blockId))
    }

    public func moveBlock(id blockId: UUID, to position: CGPoint) async throws {
        guard let block = currentConfiguration.blocks.first(where: { $0.id == blockId }) else {
            throw BlockManagerError.blockNotFoundError(blockId)
        }

        let updatedBlock = try block.movingTo(position)
        currentConfiguration = try currentConfiguration.updatingBlock(updatedBlock)

        eventPublisher.send(.blockMoved(blockId, position))
    }

    public func updateBlockParameter(blockId: UUID, parameterName: String, value: Double) async throws {
        guard let block = currentConfiguration.blocks.first(where: { $0.id == blockId }) else {
            throw BlockManagerError.blockNotFoundError(blockId)
        }

        guard block.parameters[parameterName] != nil else {
            throw BlockManagerError.parameterNotFoundError(parameterName)
        }

        let updatedBlock = try block.updatingParameter(parameterName, to: value)
        currentConfiguration = try currentConfiguration.updatingBlock(updatedBlock)

        // Update in audio engine if processing
        if isProcessing {
            try await audioService.updateBlockParameter(blockId: blockId, parameterName: parameterName, value: value)
        }

        eventPublisher.send(.blockParameterUpdated(blockId, parameterName, value))
        blockUpdatedSubject.send(updatedBlock)
    }

    // Convenience method for UI binding
    public func updateParameter(blockId: UUID, parameterName: String, value: Double) {
        Task {
            try await updateBlockParameter(blockId: blockId, parameterName: parameterName, value: value)
        }
    }

    // MARK: - Connection Management

    public func createConnection(
        from sourceBlockId: UUID,
        sourcePort: String,
        to destinationBlockId: UUID,
        destinationPort: String
    ) async throws -> Connection {
        // Validate blocks exist
        guard let sourceBlock = currentConfiguration.blocks.first(where: { $0.id == sourceBlockId }) else {
            throw BlockManagerError.blockNotFoundError(sourceBlockId)
        }

        guard let destinationBlock = currentConfiguration.blocks.first(where: { $0.id == destinationBlockId }) else {
            throw BlockManagerError.blockNotFoundError(destinationBlockId)
        }

        // Validate ports exist
        guard let sourceOutputPort = sourceBlock.outputPort(named: sourcePort) else {
            throw BlockManagerError.connectionError("Source port '\(sourcePort)' not found on block type \(sourceBlock.type)")
        }

        guard let destinationInputPort = destinationBlock.inputPort(named: destinationPort) else {
            throw BlockManagerError.connectionError("Destination port '\(destinationPort)' not found on block type \(destinationBlock.type)")
        }

        // Validate signal type compatibility
        guard sourceOutputPort.signalType.isCompatible(with: destinationInputPort.signalType) else {
            throw BlockManagerError.connectionError("Incompatible signal types: \(sourceOutputPort.signalType) cannot connect to \(destinationInputPort.signalType)")
        }

        // Create connection
        let connection = Connection(
            sourceBlockId: sourceBlockId,
            sourcePort: sourcePort,
            destinationBlockId: destinationBlockId,
            destinationPort: destinationPort,
            signalType: sourceOutputPort.signalType,
            isActive: true
        )

        // Add to configuration
        currentConfiguration = try currentConfiguration.addingConnection(connection)

        // Connect in audio engine if processing
        if isProcessing {
            try await audioService.connectBlocks(
                from: sourceBlockId, sourcePort: sourcePort,
                to: destinationBlockId, destinationPort: destinationPort
            )
        }

        eventPublisher.send(.connectionCreated(connection))
        return connection
    }

    public func removeConnection(id connectionId: UUID) async throws {
        guard let connection = currentConfiguration.connections.first(where: { $0.id == connectionId }) else {
            throw BlockManagerError.connectionNotFoundError(connectionId)
        }

        // Disconnect in audio engine if processing
        if isProcessing {
            await audioService.disconnectBlocks(
                from: connection.sourceBlockId, sourcePort: connection.sourcePort,
                to: connection.destinationBlockId, destinationPort: connection.destinationPort
            )
        }

        // Remove from configuration
        currentConfiguration = try currentConfiguration.removingConnection(connectionId)

        eventPublisher.send(.connectionRemoved(connectionId))
    }

    public func validateConnection(
        from sourceBlockId: UUID,
        sourcePort: String,
        to destinationBlockId: UUID,
        destinationPort: String
    ) async -> Bool {
        // Check basic conditions
        guard sourceBlockId != destinationBlockId else { return false }

        guard let sourceBlock = currentConfiguration.blocks.first(where: { $0.id == sourceBlockId }),
              let destinationBlock = currentConfiguration.blocks.first(where: { $0.id == destinationBlockId }) else {
            return false
        }

        guard let sourceOutputPort = sourceBlock.outputPort(named: sourcePort),
              let destinationInputPort = destinationBlock.inputPort(named: destinationPort) else {
            return false
        }

        // Check signal type compatibility
        guard sourceOutputPort.signalType.isCompatible(with: destinationInputPort.signalType) else {
            return false
        }

        // Check if destination port is already connected
        let existingConnection = currentConfiguration.connections.first { connection in
            connection.destinationBlockId == destinationBlockId && connection.destinationPort == destinationPort
        }
        guard existingConnection == nil else { return false }

        // Check for cycles
        let testConnection = Connection(
            sourceBlockId: sourceBlockId,
            sourcePort: sourcePort,
            destinationBlockId: destinationBlockId,
            destinationPort: destinationPort,
            signalType: sourceOutputPort.signalType
        )

        return !currentConfiguration.connections.wouldCreateCycle(adding: testConnection)
    }

    // MARK: - Configuration Management

    public func getCurrentConfiguration() async -> BlockConfiguration {
        return currentConfiguration
    }

    public func loadConfiguration(from url: URL) async throws -> BlockConfiguration {
        do {
            let loadedConfig = try BlockConfiguration.fromFile(url)

            // Stop current processing
            if isProcessing {
                await stopAudioProcessing()
            }

            // Update current configuration
            currentConfiguration = loadedConfig

            eventPublisher.send(.configurationLoaded(loadedConfig))
            return loadedConfig
        } catch {
            throw BlockManagerError.configurationLoadError("Failed to load configuration: \(error.localizedDescription)")
        }
    }

    public func saveConfiguration(to url: URL) async throws {
        do {
            try currentConfiguration.saveToFile(url)
            eventPublisher.send(.configurationSaved(url))
        } catch {
            throw BlockManagerError.configurationSaveError("Failed to save configuration: \(error.localizedDescription)")
        }
    }

    public func clearConfiguration() async {
        // Stop processing
        if isProcessing {
            await stopAudioProcessing()
        }

        // Clear configuration
        currentConfiguration = currentConfiguration.cleared()
    }

    // MARK: - Audio Engine Integration

    public func startAudioProcessing() async throws {
        print("🔧 [DEBUG] BlockManagerService.startAudioProcessing() - Starting")
        print("🔧 [DEBUG] BlockManagerService.startAudioProcessing() - isProcessing: \(isProcessing)")
        guard !isProcessing else {
            print("🔧 [DEBUG] BlockManagerService.startAudioProcessing() - Already processing, returning")
            return
        }

        print("🔧 [DEBUG] BlockManagerService.startAudioProcessing() - Current configuration has \(currentConfiguration.blocks.count) blocks, \(currentConfiguration.connections.count) connections")

        do {
            // Initialize audio engine
            print("🔧 [DEBUG] BlockManagerService.startAudioProcessing() - Initializing audio engine")
            try await audioService.initializeAudioEngine(sampleRate: 48000, bufferSize: 512)

            // Register all blocks
            print("🔧 [DEBUG] BlockManagerService.startAudioProcessing() - Registering \(currentConfiguration.blocks.count) blocks")
            for block in currentConfiguration.blocks {
                print("🔧 [DEBUG] BlockManagerService.startAudioProcessing() - Registering block: \(block.title) (\(block.type))")
                try await audioService.registerBlock(block)
            }

            // Create all connections
            print("🔧 [DEBUG] BlockManagerService.startAudioProcessing() - Creating \(currentConfiguration.connections.count) connections")
            for connection in currentConfiguration.connections {
                print("🔧 [DEBUG] BlockManagerService.startAudioProcessing() - Creating connection: \(connection.sourcePort) -> \(connection.destinationPort)")
                try await audioService.connectBlocks(
                    from: connection.sourceBlockId, sourcePort: connection.sourcePort,
                    to: connection.destinationBlockId, destinationPort: connection.destinationPort
                )
            }

            // Start engine
            print("🔧 [DEBUG] BlockManagerService.startAudioProcessing() - Starting audio engine")
            try await audioService.startEngine()

            isProcessing = true
            print("🔧 [DEBUG] BlockManagerService.startAudioProcessing() - Audio processing started successfully, sending event")
            eventPublisher.send(.audioProcessingStarted)
        } catch {
            print("🔧 [ERROR] BlockManagerService.startAudioProcessing() - Error: \(error)")
            throw BlockManagerError.audioEngineError("Failed to start audio processing: \(error.localizedDescription)")
        }
    }

    public func stopAudioProcessing() async {
        guard isProcessing else { return }

        await audioService.stopEngine()
        isProcessing = false
        eventPublisher.send(.audioProcessingStopped)
    }

    public func isAudioProcessing() async -> Bool {
        return isProcessing
    }

    public func setOutputDevice(_ device: OutputDevice) async throws {
        do {
            try await audioService.setOutputDevice(device)
            eventPublisher.send(.outputDeviceChanged(device))
        } catch {
            throw BlockManagerError.audioDeviceError("Failed to set output device: \(error.localizedDescription)")
        }
    }

    // MARK: - Event Publishing

    public var events: AnyPublisher<BlockManagerEvent, Never> {
        eventPublisher.eraseToAnyPublisher()
    }
}

// MARK: - Error Types

public enum BlockManagerError: Error, LocalizedError {
    case blockCreationError(String)
    case blockNotFoundError(UUID)
    case parameterNotFoundError(String)
    case invalidParameterValueError(String, Double)
    case connectionError(String)
    case connectionNotFoundError(UUID)
    case configurationLoadError(String)
    case configurationSaveError(String)
    case audioEngineError(String)
    case audioDeviceError(String)

    public var errorDescription: String? {
        switch self {
        case .blockCreationError(let message):
            return "Block creation error: \(message)"
        case .blockNotFoundError(let id):
            return "Block not found: \(id)"
        case .parameterNotFoundError(let parameter):
            return "Parameter not found: \(parameter)"
        case .invalidParameterValueError(let parameter, let value):
            return "Invalid value \(value) for parameter \(parameter)"
        case .connectionError(let message):
            return "Connection error: \(message)"
        case .connectionNotFoundError(let id):
            return "Connection not found: \(id)"
        case .configurationLoadError(let message):
            return "Configuration load error: \(message)"
        case .configurationSaveError(let message):
            return "Configuration save error: \(message)"
        case .audioEngineError(let message):
            return "Audio engine error: \(message)"
        case .audioDeviceError(let message):
            return "Audio device error: \(message)"
        }
    }
}

// MARK: - Event Types

/// Events published by the BlockManagerService
public enum BlockManagerEvent {
    case blockCreated(SignalBlock)
    case blockRemoved(UUID)
    case blockMoved(UUID, CGPoint)
    case blockParameterUpdated(UUID, String, Double)
    case connectionCreated(Connection)
    case connectionRemoved(UUID)
    case configurationLoaded(BlockConfiguration)
    case configurationSaved(URL)
    case audioProcessingStarted
    case audioProcessingStopped
    case outputDeviceChanged(OutputDevice)
}
