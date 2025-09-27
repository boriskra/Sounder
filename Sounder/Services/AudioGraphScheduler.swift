import Foundation
import AVFoundation

/// Audio Graph Scheduler processes blocks in topological order for real-time audio processing
/// Manages the execution order of AudioBlocks based on their connection dependencies
public class AudioGraphScheduler {

    // MARK: - Types

    /// Execution node containing a block and its processing order
    public struct ExecutionNode {
        let block: AudioBlock
        let executionOrder: Int
        let inputConnections: [Connection]
        let outputConnections: [Connection]
    }

    /// Audio buffer for inter-block communication
    public struct AudioBuffer {
        let blockId: UUID
        let portName: String
        let samples: [Float]

        init(blockId: UUID, portName: String, frameCount: Int) {
            self.blockId = blockId
            self.portName = portName
            self.samples = Array(repeating: 0.0, count: frameCount)
        }

        init(blockId: UUID, portName: String, samples: [Float]) {
            self.blockId = blockId
            self.portName = portName
            self.samples = samples
        }
    }

    // MARK: - Private Properties

    private var executionNodes: [ExecutionNode] = []
    private var audioBuffers: [String: AudioBuffer] = [:]
    private var processingOrder: [UUID] = []
    private let frameSize: Int
    private var timeline: AudioTimeline

    // MARK: - Initialization

    public init(frameSize: Int = 512, sampleRate: Double = 48000.0) {
        self.frameSize = frameSize
        self.timeline = AudioTimeline(sampleRate: sampleRate)
        print("🗓️ [DEBUG] AudioGraphScheduler.init() - Created with frameSize: \(frameSize), sampleRate: \(sampleRate)")
    }

    // MARK: - Public Interface

    /// Builds the execution graph from blocks and connections
    /// - Parameters:
    ///   - blocks: Dictionary of registered audio blocks
    ///   - connections: Array of active connections between blocks
    /// - Throws: AudioGraphError if the graph contains cycles or invalid connections
    public func buildExecutionGraph(
        blocks: [UUID: AudioBlock],
        connections: [Connection]
    ) throws {
        print("🗓️ [DEBUG] AudioGraphScheduler.buildExecutionGraph() - Building graph with \(blocks.count) blocks, \(connections.count) connections")

        // Validate graph doesn't contain cycles
        if connections.hasCycle() {
            throw AudioGraphError.cyclicGraph
        }

        // Validate port constraints
        let portConflicts = connections.validateInputPortConstraints()
        if !portConflicts.isEmpty {
            throw AudioGraphError.portConflicts(portConflicts)
        }

        // Calculate topological order
        let topologicalOrder = try calculateTopologicalOrder(blocks: blocks, connections: connections)

        // Build execution nodes
        executionNodes = try buildExecutionNodes(
            blocks: blocks,
            connections: connections,
            topologicalOrder: topologicalOrder
        )

        // Store processing order for debugging
        processingOrder = topologicalOrder

        // Initialize audio buffers
        initializeAudioBuffers(blocks: blocks, connections: connections)

        print("🗓️ [DEBUG] AudioGraphScheduler.buildExecutionGraph() - Built execution graph with \(executionNodes.count) nodes")
        print("🗓️ [DEBUG] AudioGraphScheduler.buildExecutionGraph() - Processing order: \(processingOrder.map { blocks[$0]?.type ?? .audioOutput })")
    }

    /// Processes one frame of audio through the entire graph with timeline coherence
    /// - Returns: Dictionary of output buffers keyed by "blockId:portName"
    public func processFrame() -> [String: [Float]] {
        var frameOutputs: [String: [Float]] = [:]

        // Clear previous frame buffers
        clearAudioBuffers()

        // Process each node in topological order with timeline context
        for node in executionNodes {
            let blockInputs = gatherInputsForBlock(node: node)
            let blockOutputs = node.block.processAudio(
                inputs: blockInputs,
                frameCount: frameSize,
                startSample: timeline.currentSample,
                sampleRate: timeline.sampleRate
            )

            // Store outputs in buffer pool
            for (portName, samples) in blockOutputs {
                let bufferKey = "\(node.block.id):\(portName)"
                audioBuffers[bufferKey] = AudioBuffer(
                    blockId: node.block.id,
                    portName: portName,
                    samples: samples
                )
                frameOutputs[bufferKey] = samples
            }
        }

        // Advance timeline for next frame
        timeline.advance(by: frameSize)
        return frameOutputs
    }

    /// Gets the current processing order for debugging
    public func getProcessingOrder() -> [UUID] {
        return processingOrder
    }

    /// Gets execution statistics for monitoring
    public func getExecutionStats() -> AudioGraphStats {
        return AudioGraphStats(
            nodeCount: executionNodes.count,
            bufferCount: audioBuffers.count,
            processingOrder: processingOrder
        )
    }

    // MARK: - Private Graph Building

    private func calculateTopologicalOrder(
        blocks: [UUID: AudioBlock],
        connections: [Connection]
    ) throws -> [UUID] {
        print("🗓️ [DEBUG] AudioGraphScheduler.calculateTopologicalOrder() - Starting topological sort")

        // Build adjacency list and in-degree count
        var graph: [UUID: Set<UUID>] = [:]
        var inDegree: [UUID: Int] = [:]

        // Initialize all blocks
        for blockId in blocks.keys {
            graph[blockId] = Set()
            inDegree[blockId] = 0
        }

        // Build graph from connections
        for connection in connections where connection.isActive {
            graph[connection.sourceBlockId]?.insert(connection.destinationBlockId)
            inDegree[connection.destinationBlockId] = (inDegree[connection.destinationBlockId] ?? 0) + 1
        }

        // Kahn's algorithm for topological sorting
        var queue: [UUID] = []
        var result: [UUID] = []

        // Add all nodes with no incoming edges
        for (blockId, degree) in inDegree where degree == 0 {
            queue.append(blockId)
        }

        while !queue.isEmpty {
            let currentBlock = queue.removeFirst()
            result.append(currentBlock)

            // Process all neighbors
            if let neighbors = graph[currentBlock] {
                for neighbor in neighbors {
                    inDegree[neighbor] = (inDegree[neighbor] ?? 0) - 1
                    if inDegree[neighbor] == 0 {
                        queue.append(neighbor)
                    }
                }
            }
        }

        // Check if all nodes were processed (no cycles)
        if result.count != blocks.count {
            throw AudioGraphError.cyclicGraph
        }

        print("🗓️ [DEBUG] AudioGraphScheduler.calculateTopologicalOrder() - Completed with order: \(result)")
        return result
    }

    private func buildExecutionNodes(
        blocks: [UUID: AudioBlock],
        connections: [Connection],
        topologicalOrder: [UUID]
    ) throws -> [ExecutionNode] {
        var nodes: [ExecutionNode] = []

        for (index, blockId) in topologicalOrder.enumerated() {
            guard let block = blocks[blockId] else {
                throw AudioGraphError.missingBlock(blockId)
            }

            let inputConnections = connections.connectionsTo(blockId).filter(\.isActive)
            let outputConnections = connections.connectionsFrom(blockId).filter(\.isActive)

            let node = ExecutionNode(
                block: block,
                executionOrder: index,
                inputConnections: inputConnections,
                outputConnections: outputConnections
            )

            nodes.append(node)
        }

        return nodes
    }

    private func initializeAudioBuffers(blocks: [UUID: AudioBlock], connections: [Connection]) {
        audioBuffers.removeAll()

        // Pre-allocate buffers for all output ports
        for (blockId, block) in blocks {
            for portName in block.outputPorts {
                let bufferKey = "\(blockId):\(portName)"
                audioBuffers[bufferKey] = AudioBuffer(
                    blockId: blockId,
                    portName: portName,
                    frameCount: frameSize
                )
            }
        }

        print("🗓️ [DEBUG] AudioGraphScheduler.initializeAudioBuffers() - Initialized \(audioBuffers.count) buffers")
    }

    // MARK: - Private Audio Processing

    private func clearAudioBuffers() {
        for (key, buffer) in audioBuffers {
            audioBuffers[key] = AudioBuffer(
                blockId: buffer.blockId,
                portName: buffer.portName,
                frameCount: frameSize
            )
        }
    }

    private func gatherInputsForBlock(node: ExecutionNode) -> [String: [Float]] {
        var inputs: [String: [Float]] = [:]

        for connection in node.inputConnections {
            let sourceBufferKey = "\(connection.sourceBlockId):\(connection.sourcePort)"

            if let sourceBuffer = audioBuffers[sourceBufferKey] {
                inputs[connection.destinationPort] = sourceBuffer.samples
            } else {
                // Provide silent buffer if source not available
                inputs[connection.destinationPort] = Array(repeating: 0.0, count: frameSize)
                print("🗓️ [WARNING] AudioGraphScheduler.gatherInputsForBlock() - Missing buffer for \(sourceBufferKey), using silence")
            }
        }

        return inputs
    }
}

// MARK: - Supporting Types

/// Statistics about the audio graph execution
public struct AudioGraphStats {
    public let nodeCount: Int
    public let bufferCount: Int
    public let processingOrder: [UUID]
}

/// Errors that can occur during audio graph processing
public enum AudioGraphError: Error, LocalizedError {
    case cyclicGraph
    case portConflicts([PortConflict])
    case missingBlock(UUID)
    case invalidConnection(Connection)
    case bufferUnderrun

    public var errorDescription: String? {
        switch self {
        case .cyclicGraph:
            return "Audio graph contains cycles - feedback loops are not supported"
        case .portConflicts(let conflicts):
            return "Port conflicts detected: \(conflicts.count) ports have multiple inputs"
        case .missingBlock(let blockId):
            return "Missing block in execution graph: \(blockId)"
        case .invalidConnection(let connection):
            return "Invalid connection: \(connection.sourcePort) -> \(connection.destinationPort)"
        case .bufferUnderrun:
            return "Audio buffer underrun detected during processing"
        }
    }
}

// MARK: - Extensions

extension AudioGraphScheduler {
    /// Validates that the current graph is valid for audio processing
    public func validateGraph() throws {
        guard !executionNodes.isEmpty else {
            throw AudioGraphError.bufferUnderrun
        }

        // Additional validation logic can be added here
        print("🗓️ [DEBUG] AudioGraphScheduler.validateGraph() - Graph validation passed")
    }

    /// Gets detailed information about a specific execution node
    public func getNodeInfo(for blockId: UUID) -> ExecutionNode? {
        return executionNodes.first { $0.block.id == blockId }
    }

    /// Gets the current buffer state for debugging
    public func getBufferState() -> [String: Int] {
        return audioBuffers.mapValues { $0.samples.count }
    }

    // MARK: - Timeline Management

    /// Resets the audio timeline and all blocks to the beginning
    public func resetTimeline() {
        timeline.reset()
        resetAllBlocks()
        print("🗓️ [DEBUG] AudioGraphScheduler.resetTimeline() - Timeline and blocks reset to sample 0")
    }

    /// Resets the timeline to a specific sample position
    /// - Parameter sample: Sample position to reset to
    public func resetTimeline(to sample: UInt64) {
        timeline.reset(to: sample)
        resetAllBlocks(to: sample)
        print("🗓️ [DEBUG] AudioGraphScheduler.resetTimeline(to:) - Timeline and blocks reset to sample \(sample)")
    }

    /// Gets the current timeline statistics
    public func getTimelineStats() -> AudioTimelineStats {
        return timeline.getStats()
    }

    /// Gets the current sample position in the timeline
    public func getCurrentSample() -> UInt64 {
        return timeline.currentSample
    }

    /// Gets the current time in seconds since timeline start
    public func getCurrentTime() -> Double {
        return timeline.currentTime
    }

    /// Validates the timeline state
    /// - Throws: AudioTimelineError if validation fails
    public func validateTimeline() throws {
        try timeline.validate()
    }

    // MARK: - Private Timeline Methods

    private func resetAllBlocks() {
        for node in executionNodes {
            node.block.reset(to: 0, sampleRate: timeline.sampleRate)
        }
    }

    private func resetAllBlocks(to sample: UInt64) {
        for node in executionNodes {
            node.block.reset(to: sample, sampleRate: timeline.sampleRate)
        }
    }
}