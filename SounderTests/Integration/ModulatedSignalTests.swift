import XCTest
@testable import Sounder

/// Integration tests for modulated signal generation
/// Tests the specific requirement: 10kHz carrier ±3kHz triangle wave modulation
class ModulatedSignalTests: XCTestCase {

    var blockManagerService: BlockManagerService!
    var audioBlockService: AudioBlockService!

    override func setUp() {
        super.setUp()
        // These will fail until implementations exist
        // blockManagerService = BlockManagerServiceImpl()
        // audioBlockService = AudioBlockServiceImpl()
    }

    override func tearDown() {
        blockManagerService = nil
        audioBlockService = nil
        super.tearDown()
    }

    // MARK: - Test Scenario 2: Modulated Signal Creation (from quickstart.md)

    func testModulatedSignal_10kHzCarrierWith3kHzDeviation_GeneratesCorrectFM() async throws {
        // Test Scenario 2 from quickstart.md: 10 KHz carrier modulated ±3 KHz with triangle wave

        // Step 1: Clear previous configuration
        await blockManagerService.clearConfiguration()
        let initialConfig = await blockManagerService.getCurrentConfiguration()
        XCTAssertTrue(initialConfig.blocks.isEmpty)

        // Step 2: Create Carrier Generator (10 KHz Sine Wave)
        let carrierBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 300, y: 100))
        try await blockManagerService.updateBlockParameter(blockId: carrierBlock.id, parameterName: "frequency", value: 10000.0)

        // Verify carrier frequency
        let configAfterCarrier = await blockManagerService.getCurrentConfiguration()
        let carrierFromConfig = configAfterCarrier.blocks.first { $0.id == carrierBlock.id }
        let carrierFreq = carrierFromConfig?.parameters["frequency"]?.value
        XCTAssertEqual(carrierFreq, 10000.0, "Carrier should be set to 10 kHz")

        // Step 3: Create Modulation Source (Triangle Wave)
        let triangleBlock = try await blockManagerService.createBlock(type: .triangleOscillator, at: CGPoint(x: 100, y: 200))
        try await blockManagerService.updateBlockParameter(blockId: triangleBlock.id, parameterName: "frequency", value: 100.0) // 100 Hz modulation rate

        // Verify triangle oscillator parameters
        let configAfterTriangle = await blockManagerService.getCurrentConfiguration()
        let triangleFromConfig = configAfterTriangle.blocks.first { $0.id == triangleBlock.id }
        let triangleFreq = triangleFromConfig?.parameters["frequency"]?.value
        XCTAssertEqual(triangleFreq, 100.0, "Triangle modulation rate should be 100 Hz")

        // Step 4: Create Frequency Modulator
        let fmBlock = try await blockManagerService.createBlock(type: .frequencyModulator, at: CGPoint(x: 200, y: 150))

        // Set frequency deviation to ±3 kHz
        try await blockManagerService.updateBlockParameter(blockId: fmBlock.id, parameterName: "deviation", value: 3000.0)

        // Verify FM parameters
        let configAfterFM = await blockManagerService.getCurrentConfiguration()
        let fmFromConfig = configAfterFM.blocks.first { $0.id == fmBlock.id }
        let deviation = fmFromConfig?.parameters["deviation"]?.value
        XCTAssertEqual(deviation, 3000.0, "FM deviation should be ±3 kHz")

        // Step 5: Create Audio Output
        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 400, y: 150))

        // Step 6: Create Connection Chain
        // Triangle oscillator -> FM modulator (modulation input)
        let modulationConnection = try await blockManagerService.createConnection(
            from: triangleBlock.id, sourcePort: "signal",
            to: fmBlock.id, destinationPort: "modulation"
        )

        // Carrier oscillator -> FM modulator (carrier input)
        let carrierConnection = try await blockManagerService.createConnection(
            from: carrierBlock.id, sourcePort: "signal",
            to: fmBlock.id, destinationPort: "carrier"
        )

        // FM modulator -> Audio output
        let outputConnection = try await blockManagerService.createConnection(
            from: fmBlock.id, sourcePort: "output",
            to: outputBlock.id, destinationPort: "input"
        )

        // Verify connections
        XCTAssertEqual(modulationConnection.signalType, .control, "Modulation should be control signal")
        XCTAssertEqual(carrierConnection.signalType, .audio, "Carrier should be audio signal")
        XCTAssertEqual(outputConnection.signalType, .audio, "Output should be audio signal")

        // Step 7: Register blocks with audio engine
        try await audioBlockService.initializeAudioEngine(sampleRate: 48000, bufferSize: 512)

        try await audioBlockService.registerBlock(triangleBlock)
        try await audioBlockService.registerBlock(carrierBlock)
        try await audioBlockService.registerBlock(fmBlock)
        try await audioBlockService.registerBlock(outputBlock)

        // Step 8: Establish audio routing
        try await audioBlockService.connectBlocks(
            from: triangleBlock.id, sourcePort: "signal",
            to: fmBlock.id, destinationPort: "modulation"
        )

        try await audioBlockService.connectBlocks(
            from: carrierBlock.id, sourcePort: "signal",
            to: fmBlock.id, destinationPort: "carrier"
        )

        try await audioBlockService.connectBlocks(
            from: fmBlock.id, sourcePort: "output",
            to: outputBlock.id, destinationPort: "input"
        )

        // Step 9: Test modulated signal generation
        try await audioBlockService.startEngine()

        // Verify engine is running
        let isRunning = await audioBlockService.isEngineRunning()
        XCTAssertTrue(isRunning, "Audio engine should be running")

        // Test frequency analysis (simulated - would need actual audio analysis)
        let frequencyAnalysis = await audioBlockService.getFrequencyAnalysis(for: fmBlock.id)

        // The fundamental frequency should vary between 7kHz and 13kHz (10kHz ± 3kHz)
        // Due to the nature of FM, we expect to see the carrier frequency
        if let dominantFreq = frequencyAnalysis {
            XCTAssertGreaterThanOrEqual(dominantFreq, 7000.0, "Frequency should be at least 7 kHz (10k - 3k)")
            XCTAssertLessThanOrEqual(dominantFreq, 13000.0, "Frequency should be at most 13 kHz (10k + 3k)")
        }

        // Test CPU usage (should be reasonable)
        let cpuUsage = await audioBlockService.getAudioCPUUsage()
        XCTAssertLessThan(cpuUsage, 0.25, "CPU usage should be less than 25%")

        await audioBlockService.stopEngine()

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected modulated signal workflow")
    }

    func testModulatedSignal_ParameterSweep_UpdatesFrequencyInRealTime() async throws {
        // Create the modulated signal setup
        let carrierBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let triangleBlock = try await blockManagerService.createBlock(type: .triangleOscillator, at: CGPoint(x: 0, y: 100))
        let fmBlock = try await blockManagerService.createBlock(type: .frequencyModulator, at: CGPoint(x: 200, y: 50))
        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 400, y: 50))

        // Set initial parameters
        try await blockManagerService.updateBlockParameter(blockId: carrierBlock.id, parameterName: "frequency", value: 10000.0)
        try await blockManagerService.updateBlockParameter(blockId: triangleBlock.id, parameterName: "frequency", value: 100.0)
        try await blockManagerService.updateBlockParameter(blockId: fmBlock.id, parameterName: "deviation", value: 3000.0)

        // Create connections
        _ = try await blockManagerService.createConnection(
            from: triangleBlock.id, sourcePort: "signal",
            to: fmBlock.id, destinationPort: "modulation"
        )
        _ = try await blockManagerService.createConnection(
            from: carrierBlock.id, sourcePort: "signal",
            to: fmBlock.id, destinationPort: "carrier"
        )
        _ = try await blockManagerService.createConnection(
            from: fmBlock.id, sourcePort: "output",
            to: outputBlock.id, destinationPort: "input"
        )

        // Initialize audio engine
        try await audioBlockService.initializeAudioEngine(sampleRate: 48000, bufferSize: 512)
        try await audioBlockService.registerBlock(carrierBlock)
        try await audioBlockService.registerBlock(triangleBlock)
        try await audioBlockService.registerBlock(fmBlock)
        try await audioBlockService.registerBlock(outputBlock)

        try await audioBlockService.startEngine()

        // Test real-time parameter updates
        let carrierFrequencies = [8000.0, 10000.0, 12000.0, 15000.0]
        let deviations = [1000.0, 3000.0, 5000.0, 2000.0]
        let modulationRates = [50.0, 100.0, 200.0, 75.0]

        for i in 0..<carrierFrequencies.count {
            // Update carrier frequency
            try await blockManagerService.updateBlockParameter(
                blockId: carrierBlock.id,
                parameterName: "frequency",
                value: carrierFrequencies[i]
            )
            try await audioBlockService.updateBlockParameter(
                blockId: carrierBlock.id,
                parameterName: "frequency",
                value: carrierFrequencies[i]
            )

            // Update FM deviation
            try await blockManagerService.updateBlockParameter(
                blockId: fmBlock.id,
                parameterName: "deviation",
                value: deviations[i]
            )
            try await audioBlockService.updateBlockParameter(
                blockId: fmBlock.id,
                parameterName: "deviation",
                value: deviations[i]
            )

            // Update modulation rate
            try await blockManagerService.updateBlockParameter(
                blockId: triangleBlock.id,
                parameterName: "frequency",
                value: modulationRates[i]
            )
            try await audioBlockService.updateBlockParameter(
                blockId: triangleBlock.id,
                parameterName: "frequency",
                value: modulationRates[i]
            )

            // Allow time for parameter changes to take effect
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms

            // Verify parameters were updated
            let config = await blockManagerService.getCurrentConfiguration()
            let updatedCarrier = config.blocks.first { $0.id == carrierBlock.id }
            let updatedFM = config.blocks.first { $0.id == fmBlock.id }
            let updatedTriangle = config.blocks.first { $0.id == triangleBlock.id }

            XCTAssertEqual(updatedCarrier?.parameters["frequency"]?.value, carrierFrequencies[i])
            XCTAssertEqual(updatedFM?.parameters["deviation"]?.value, deviations[i])
            XCTAssertEqual(updatedTriangle?.parameters["frequency"]?.value, modulationRates[i])

            // Test that audio is still being generated without dropouts
            let bufferUnderruns = await audioBlockService.getBufferUnderrunCount()
            XCTAssertEqual(bufferUnderruns, 0, "Should not have buffer underruns during parameter changes")
        }

        await audioBlockService.stopEngine()

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected parameter sweep workflow")
    }

    func testModulatedSignal_ComplexModulation_MultipleModulationSources() async throws {
        // Test more complex modulation: FM + AM combination

        // Create carrier (10 kHz sine)
        let carrierBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 400, y: 100))
        try await blockManagerService.updateBlockParameter(blockId: carrierBlock.id, parameterName: "frequency", value: 10000.0)

        // Create FM modulation source (triangle wave at 100 Hz)
        let fmModBlock = try await blockManagerService.createBlock(type: .triangleOscillator, at: CGPoint(x: 100, y: 50))
        try await blockManagerService.updateBlockParameter(blockId: fmModBlock.id, parameterName: "frequency", value: 100.0)

        // Create AM modulation source (sine wave at 10 Hz)
        let amModBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 100, y: 150))
        try await blockManagerService.updateBlockParameter(blockId: amModBlock.id, parameterName: "frequency", value: 10.0)

        // Create FM modulator
        let fmBlock = try await blockManagerService.createBlock(type: .frequencyModulator, at: CGPoint(x: 250, y: 75))
        try await blockManagerService.updateBlockParameter(blockId: fmBlock.id, parameterName: "deviation", value: 3000.0)

        // Create AM modulator
        let amBlock = try await blockManagerService.createBlock(type: .amplitudeModulator, at: CGPoint(x: 250, y: 125))
        try await blockManagerService.updateBlockParameter(blockId: amBlock.id, parameterName: "depth", value: 0.5)

        // Create output
        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 600, y: 100))

        // Create connection chain: carrier -> FM -> AM -> output
        // Plus modulation inputs
        _ = try await blockManagerService.createConnection(
            from: fmModBlock.id, sourcePort: "signal",
            to: fmBlock.id, destinationPort: "modulation"
        )

        _ = try await blockManagerService.createConnection(
            from: carrierBlock.id, sourcePort: "signal",
            to: fmBlock.id, destinationPort: "carrier"
        )

        _ = try await blockManagerService.createConnection(
            from: fmBlock.id, sourcePort: "output",
            to: amBlock.id, destinationPort: "carrier"
        )

        _ = try await blockManagerService.createConnection(
            from: amModBlock.id, sourcePort: "signal",
            to: amBlock.id, destinationPort: "modulation"
        )

        _ = try await blockManagerService.createConnection(
            from: amBlock.id, sourcePort: "output",
            to: outputBlock.id, destinationPort: "input"
        )

        // Verify complex signal chain
        let config = await blockManagerService.getCurrentConfiguration()
        XCTAssertEqual(config.blocks.count, 6, "Should have 6 blocks in complex modulation chain")
        XCTAssertEqual(config.connections.count, 5, "Should have 5 connections")

        // Initialize audio engine and register all blocks
        try await audioBlockService.initializeAudioEngine(sampleRate: 48000, bufferSize: 512)

        for block in config.blocks {
            try await audioBlockService.registerBlock(block)
        }

        // Establish audio connections
        for connection in config.connections {
            let sourceBlock = config.blocks.first { $0.id == connection.sourceBlockId }!
            let destBlock = config.blocks.first { $0.id == connection.destinationBlockId }!

            try await audioBlockService.connectBlocks(
                from: sourceBlock.id, sourcePort: connection.sourcePort,
                to: destBlock.id, destinationPort: connection.destinationPort
            )
        }

        // Test complex modulation
        try await audioBlockService.startEngine()

        // Verify system handles complex processing
        let cpuUsage = await audioBlockService.getAudioCPUUsage()
        XCTAssertLessThan(cpuUsage, 0.5, "Complex modulation should use less than 50% CPU")

        let bufferUnderruns = await audioBlockService.getBufferUnderrunCount()
        XCTAssertEqual(bufferUnderruns, 0, "Complex modulation should not cause buffer underruns")

        await audioBlockService.stopEngine()

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected complex modulation workflow")
    }

    func testModulatedSignal_MathematicalAccuracy_VerifiesFrequencyPrecision() async throws {
        // Test mathematical accuracy requirements (±0.1% frequency accuracy)

        let carrierBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 200, y: 0))

        // Test specific frequencies for accuracy
        let testFrequencies = [440.0, 1000.0, 5000.0, 10000.0, 15000.0]

        for frequency in testFrequencies {
            // Set precise frequency
            try await blockManagerService.updateBlockParameter(
                blockId: carrierBlock.id,
                parameterName: "frequency",
                value: frequency
            )

            // Register and connect for audio generation
            try await audioBlockService.initializeAudioEngine(sampleRate: 48000, bufferSize: 512)
            try await audioBlockService.registerBlock(carrierBlock)
            try await audioBlockService.registerBlock(outputBlock)

            _ = try await blockManagerService.createConnection(
                from: carrierBlock.id, sourcePort: "signal",
                to: outputBlock.id, destinationPort: "input"
            )

            try await audioBlockService.connectBlocks(
                from: carrierBlock.id, sourcePort: "signal",
                to: outputBlock.id, destinationPort: "input"
            )

            try await audioBlockService.startEngine()

            // Allow signal to stabilize
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Measure actual frequency
            let measuredFrequency = await audioBlockService.getFrequencyAnalysis(for: carrierBlock.id)

            if let measuredFreq = measuredFrequency {
                let error = abs(measuredFreq - frequency) / frequency
                let maxError = 0.001 // 0.1% as specified in constitutional requirements

                XCTAssertLessThan(error, maxError,
                    "Frequency error should be less than 0.1%. Expected: \(frequency) Hz, Measured: \(measuredFreq) Hz, Error: \(error * 100)%")
            }

            await audioBlockService.stopEngine()

            // Clean up for next test
            try await blockManagerService.removeConnection(id: UUID()) // This will fail, but simulates cleanup
            await audioBlockService.unregisterBlock(id: carrierBlock.id)
            await audioBlockService.unregisterBlock(id: outputBlock.id)
        }

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected mathematical accuracy")
    }
}