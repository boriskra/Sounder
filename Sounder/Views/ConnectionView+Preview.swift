import SwiftUI

/// Preview setup for `ConnectionView` showcasing a sample connection between two blocks.
#Preview {
    let sampleConnection: BlockConnection = BlockConnection(
        outputBlockId: UUID(),
        outputPort: "signal",
        inputBlockId: UUID(),
        inputPort: "frequency"
    )

    let sampleBlocks: [SignalBlock] = [
        SignalBlock(
            type: .sineOscillator,
            title: "Sine Wave",
            position: CGPoint(x: 100, y: 100),
            parameters: [:],
            inputPorts: [InputPort(name: "frequency", displayName: "Frequency", signalType: .frequency, isRequired: false, defaultValue: nil)],
            outputPorts: [OutputPort(name: "signal", displayName: "Signal", signalType: .audio, isRequired: false, defaultValue: nil)]
        ),
        SignalBlock(
            type: .triangleOscillator,
            title: "Triangle LFO",
            position: CGPoint(x: 300, y: 100),
            parameters: [:],
            inputPorts: [InputPort(name: "frequency", displayName: "Frequency", signalType: .frequency, isRequired: false, defaultValue: nil)],
            outputPorts: [OutputPort(name: "signal", displayName: "Signal", signalType: .audio, isRequired: false, defaultValue: nil)]
        )
    ]

    let updatedConnection: BlockConnection = BlockConnection(
        outputBlockId: sampleBlocks[0].id,
        outputPort: "signal",
        inputBlockId: sampleBlocks[1].id,
        inputPort: "frequency"
    )

    let mockBlockManager: BlockManagerServiceImpl = BlockManagerServiceImpl(audioService: MockAudioBlockService())
    let canvasService: BlockCanvasServiceImpl = BlockCanvasServiceImpl(blockManagerService: mockBlockManager)

    return ConnectionView(
        connection: updatedConnection,
        blocks: sampleBlocks,
        canvasService: canvasService,
        blockManager: mockBlockManager
    )
    .frame(width: 500, height: 300)
    .background(Color.gray.opacity(0.1))
}
