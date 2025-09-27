import Foundation
import SwiftUI
import Combine

/// Mock implementation of BlockManagerService for testing and previews
class MockBlockManagerService: BlockManagerService, ObservableObject {
    @Published var blocks: [SignalBlock] = []
    @Published var connections: [Connection] = []
    @Published var selectedBlockId: UUID?
    @Published var canvasScale: CGFloat = 1.0
    @Published var canvasOffset: CGSize = .zero

    private let audioService: AudioService

    init(audioService: AudioService = MockAudioService()) {
        self.audioService = audioService

        // Create some sample blocks for preview
        setupSampleBlocks()
    }

    // MARK: - BlockManagerService Implementation

    func createBlock(type: BlockType, at position: CGPoint) async throws -> SignalBlock {
        let newBlock = SignalBlock(
            type: type,
            title: type.displayName,
            position: position,
            parameters: type.createDefaultParameters(),
            inputPorts: type.defaultInputPorts,
            outputPorts: type.defaultOutputPorts
        )

        blocks.append(newBlock)
        return newBlock
    }

    func removeBlock(id blockId: UUID) async throws {
        blocks.removeAll { $0.id == blockId }
        connections.removeAll { $0.involvesBlock(blockId) }

        if selectedBlockId == blockId {
            selectedBlockId = nil
        }
    }

    func updateBlock(_ block: SignalBlock) {
        if let index = blocks.firstIndex(where: { $0.id == block.id }) {
            blocks[index] = block
        }
    }

    func moveBlock(id blockId: UUID, to position: CGPoint) async throws {
        if let index = blocks.firstIndex(where: { $0.id == blockId }) {
            var updatedBlock = blocks[index]
            updatedBlock.position = position
            blocks[index] = updatedBlock
        }
    }

    func createConnection(from sourceBlockId: UUID, sourcePort: String, to destinationBlockId: UUID, destinationPort: String) async throws -> Connection {
        // Validate blocks exist
        guard blocks.contains(where: { $0.id == sourceBlockId }) else {
            throw BlockManagerError.blockNotFoundError(sourceBlockId)
        }

        guard blocks.contains(where: { $0.id == destinationBlockId }) else {
            throw BlockManagerError.blockNotFoundError(destinationBlockId)
        }

        let newConnection = Connection(
            sourceBlockId: sourceBlockId,
            sourcePort: sourcePort,
            destinationBlockId: destinationBlockId,
            destinationPort: destinationPort,
            signalType: .audio, // Default to audio signal type
            isActive: true
        )

        // Check for cycles
        if connections.wouldCreateCycle(adding: newConnection) {
            throw BlockManagerError.connectionError("Connection would create a cycle")
        }

        connections.append(newConnection)
        return newConnection
    }

    func removeConnection(id connectionId: UUID) async throws {
        connections.removeAll { $0.id == connectionId }
    }

    func selectBlock(_ blockId: UUID?) {
        selectedBlockId = blockId
    }

    func getBlock(_ blockId: UUID) -> SignalBlock? {
        return blocks.first { $0.id == blockId }
    }

    func getConnections(to blockId: UUID) -> [Connection] {
        return connections.connectionsTo(blockId)
    }

    func getConnections(from blockId: UUID) -> [Connection] {
        return connections.connectionsFrom(blockId)
    }

    func updateBlockParameter(blockId: UUID, parameterName: String, value: Double) async throws {
        guard let blockIndex = blocks.firstIndex(where: { $0.id == blockId }) else { return }

        var updatedBlock = blocks[blockIndex]
        if var parameter = updatedBlock.parameters[parameterName] {
            parameter.value = value
            updatedBlock.parameters[parameterName] = parameter
            blocks[blockIndex] = updatedBlock
        }
    }

    func clearConfiguration() async {
        blocks.removeAll()
        connections.removeAll()
        selectedBlockId = nil
    }

    func getCurrentConfiguration() async -> BlockConfiguration {
        return BlockConfiguration(
            name: "Mock Configuration",
            blocks: blocks,
            connections: connections,
            metadata: [
                "description": "Generated mock configuration",
                "generator": "MockBlockManagerService"
            ]
        )
    }

    func loadConfiguration(from url: URL) async throws -> BlockConfiguration {
        // Mock implementation - return current configuration
        return await getCurrentConfiguration()
    }

    func saveConfiguration(to url: URL) async throws {
        // Mock implementation - do nothing
    }

    func importConfiguration(_ configuration: BlockConfiguration) throws {
        blocks = configuration.blocks
        connections = configuration.connections
        selectedBlockId = nil
    }

    func validateConnection(from sourceBlockId: UUID, sourcePort: String, to destinationBlockId: UUID, destinationPort: String) async -> Bool {
        // Mock validation - just check if blocks exist
        return blocks.contains(where: { $0.id == sourceBlockId }) &&
               blocks.contains(where: { $0.id == destinationBlockId })
    }

    func startAudioProcessing() async throws {
        // Mock implementation - do nothing
    }

    func stopAudioProcessing() async {
        // Mock implementation - do nothing
    }

    func isAudioProcessing() async -> Bool {
        // Mock implementation - return false
        return false
    }

    func setOutputDevice(_ device: OutputDevice) async throws {
        // Mock implementation - do nothing (AudioService doesn't have this method)
    }

    // MARK: - Private Setup

    private func setupSampleBlocks() {
        Task {
            do {
                // Create a sine oscillator
                let sineOsc = try await createBlock(type: .sineOscillator, at: CGPoint(x: 100, y: 200))

                // Create an output block
                let output = try await createBlock(type: .audioOutput, at: CGPoint(x: 400, y: 200))

                // Connect them
                let _ = try await createConnection(
                    from: sineOsc.id,
                    sourcePort: "signal",
                    to: output.id,
                    destinationPort: "input"
                )

            } catch {
                print("Failed to setup sample blocks: \(error)")
            }
        }
    }
}

// BlockManagerError is defined in BlockManagerService.swift
