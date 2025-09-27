import Foundation
import SwiftUI
import Combine
@testable import Sounder

/// Mock implementation of BlockManagerService for testing
public class MockBlockManagerService: BlockManagerService {
    private var currentConfiguration = BlockConfiguration.empty()
    private var isProcessing = false
    private var currentOutputDevice: OutputDevice?

    // MARK: - Test Configuration

    public var shouldThrowError = false
    public var errorToThrow: BlockManagerError?
    public var createdBlocks: [SignalBlock] = []
    public var removedBlockIds: [UUID] = []
    public var createdConnections: [Connection] = []
    public var removedConnectionIds: [UUID] = []
    public var savedUrls: [URL] = []
    public var loadedUrls: [URL] = []

    // MARK: - Block Management

    public func createBlock(type: BlockType, at position: CGPoint) async throws -> SignalBlock {
        if shouldThrowError {
            throw errorToThrow ?? BlockManagerError.blockCreationError("Mock error")
        }

        let block = SignalBlock(
            type: type,
            title: type.displayName,
            position: position,
            parameters: type.createDefaultParameters(),
            inputPorts: type.defaultInputPorts,
            outputPorts: type.defaultOutputPorts
        )

        currentConfiguration = try currentConfiguration.addingBlock(block)
        createdBlocks.append(block)

        return block
    }

    public func removeBlock(id blockId: UUID) async throws {
        if shouldThrowError {
            throw errorToThrow ?? BlockManagerError.blockNotFoundError(blockId)
        }

        guard currentConfiguration.blocks.contains(where: { $0.id == blockId }) else {
            throw BlockManagerError.blockNotFoundError(blockId)
        }

        currentConfiguration = try currentConfiguration.removingBlock(blockId)
        removedBlockIds.append(blockId)
    }

    public func moveBlock(id blockId: UUID, to position: CGPoint) async throws {
        if shouldThrowError {
            throw errorToThrow ?? BlockManagerError.blockNotFoundError(blockId)
        }

        guard let block = currentConfiguration.blocks.first(where: { $0.id == blockId }) else {
            throw BlockManagerError.blockNotFoundError(blockId)
        }

        let updatedBlock = try block.movingTo(position)
        currentConfiguration = try currentConfiguration.updatingBlock(updatedBlock)
    }

    public func updateBlockParameter(blockId: UUID, parameterName: String, value: Double) async throws {
        if shouldThrowError {
            throw errorToThrow ?? BlockManagerError.parameterNotFoundError(parameterName)
        }

        guard let block = currentConfiguration.blocks.first(where: { $0.id == blockId }) else {
            throw BlockManagerError.blockNotFoundError(blockId)
        }

        guard block.parameters[parameterName] != nil else {
            throw BlockManagerError.parameterNotFoundError(parameterName)
        }

        let updatedBlock = try block.updatingParameter(parameterName, to: value)
        currentConfiguration = try currentConfiguration.updatingBlock(updatedBlock)
    }

    // MARK: - Connection Management

    public func createConnection(
        from sourceBlockId: UUID,
        sourcePort: String,
        to destinationBlockId: UUID,
        destinationPort: String
    ) async throws -> Connection {
        if shouldThrowError {
            throw errorToThrow ?? BlockManagerError.connectionError("Mock connection error")
        }

        guard let sourceBlock = currentConfiguration.blocks.first(where: { $0.id == sourceBlockId }) else {
            throw BlockManagerError.blockNotFoundError(sourceBlockId)
        }

        guard let destinationBlock = currentConfiguration.blocks.first(where: { $0.id == destinationBlockId }) else {
            throw BlockManagerError.blockNotFoundError(destinationBlockId)
        }

        guard let sourceOutputPort = sourceBlock.outputPort(named: sourcePort) else {
            throw BlockManagerError.connectionError("Source port '\(sourcePort)' not found")
        }

        guard let destinationInputPort = destinationBlock.inputPort(named: destinationPort) else {
            throw BlockManagerError.connectionError("Destination port '\(destinationPort)' not found")
        }

        let connection = Connection(
            sourceBlockId: sourceBlockId,
            sourcePort: sourcePort,
            destinationBlockId: destinationBlockId,
            destinationPort: destinationPort,
            signalType: sourceOutputPort.signalType,
            isActive: true
        )

        currentConfiguration = try currentConfiguration.addingConnection(connection)
        createdConnections.append(connection)

        return connection
    }

    public func removeConnection(id connectionId: UUID) async throws {
        if shouldThrowError {
            throw errorToThrow ?? BlockManagerError.connectionNotFoundError(connectionId)
        }

        guard currentConfiguration.connections.contains(where: { $0.id == connectionId }) else {
            throw BlockManagerError.connectionNotFoundError(connectionId)
        }

        currentConfiguration = try currentConfiguration.removingConnection(connectionId)
        removedConnectionIds.append(connectionId)
    }

    public func validateConnection(
        from sourceBlockId: UUID,
        sourcePort: String,
        to destinationBlockId: UUID,
        destinationPort: String
    ) async -> Bool {
        // Simple validation - just check that blocks exist and aren't the same
        guard sourceBlockId != destinationBlockId else { return false }

        let sourceExists = currentConfiguration.blocks.contains { $0.id == sourceBlockId }
        let destExists = currentConfiguration.blocks.contains { $0.id == destinationBlockId }

        return sourceExists && destExists
    }

    // MARK: - Configuration Management

    public func getCurrentConfiguration() async -> BlockConfiguration {
        return currentConfiguration
    }

    public func loadConfiguration(from url: URL) async throws -> BlockConfiguration {
        if shouldThrowError {
            throw errorToThrow ?? BlockManagerError.configurationLoadError("Mock load error")
        }

        loadedUrls.append(url)

        // Create a mock configuration for testing
        let mockConfig = BlockConfiguration(name: "Mock Configuration")
        currentConfiguration = mockConfig
        return mockConfig
    }

    public func saveConfiguration(to url: URL) async throws {
        if shouldThrowError {
            throw errorToThrow ?? BlockManagerError.configurationSaveError("Mock save error")
        }

        savedUrls.append(url)
    }

    public func clearConfiguration() async {
        currentConfiguration = BlockConfiguration.empty()
    }

    // MARK: - Audio Engine Integration

    public func startAudioProcessing() async throws {
        if shouldThrowError {
            throw errorToThrow ?? BlockManagerError.audioEngineError("Mock audio error")
        }

        isProcessing = true
    }

    public func stopAudioProcessing() async {
        isProcessing = false
    }

    public func isAudioProcessing() async -> Bool {
        return isProcessing
    }

    public func setOutputDevice(_ device: OutputDevice) async throws {
        if shouldThrowError {
            throw errorToThrow ?? BlockManagerError.audioDeviceError("Mock device error")
        }

        currentOutputDevice = device
    }

    // MARK: - Test Helpers

    public func reset() {
        currentConfiguration = BlockConfiguration.empty()
        isProcessing = false
        currentOutputDevice = nil
        shouldThrowError = false
        errorToThrow = nil
        createdBlocks.removeAll()
        removedBlockIds.removeAll()
        createdConnections.removeAll()
        removedConnectionIds.removeAll()
        savedUrls.removeAll()
        loadedUrls.removeAll()
    }

    public func setConfiguration(_ config: BlockConfiguration) {
        currentConfiguration = config
    }

    public func getOutputDevice() -> OutputDevice? {
        return currentOutputDevice
    }
}