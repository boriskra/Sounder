import XCTest
@testable import Sounder

/// Integration tests for configuration save/load functionality
/// Tests the requirement for saving and loading complete block configurations
class ConfigurationPersistenceTests: XCTestCase {

    var blockManagerService: BlockManagerService!

    override func setUp() {
        super.setUp()
        // This will fail until implementation exists
        // blockManagerService = BlockManagerServiceImpl()
    }

    override func tearDown() {
        blockManagerService = nil
        super.tearDown()
    }

    // MARK: - Test Scenario 4: Configuration Save/Load (from quickstart.md)

    func testConfigurationPersistence_CompleteWorkflow_SaveLoadRestore() async throws {
        // Test Scenario 4 from quickstart.md: Configuration Save/Load

        // Step 1: Create complex configuration (modulated signal from Scenario 2)
        let carrierBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 300, y: 100))
        try await blockManagerService.updateBlockParameter(blockId: carrierBlock.id, parameterName: "frequency", value: 10000.0)

        let triangleBlock = try await blockManagerService.createBlock(type: .triangleOscillator, at: CGPoint(x: 100, y: 200))
        try await blockManagerService.updateBlockParameter(blockId: triangleBlock.id, parameterName: "frequency", value: 100.0)

        let fmBlock = try await blockManagerService.createBlock(type: .frequencyModulator, at: CGPoint(x: 200, y: 150))
        try await blockManagerService.updateBlockParameter(blockId: fmBlock.id, parameterName: "deviation", value: 3000.0)

        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 400, y: 150))

        // Create connections
        let modulationConnection = try await blockManagerService.createConnection(
            from: triangleBlock.id, sourcePort: "signal",
            to: fmBlock.id, destinationPort: "modulation"
        )

        let carrierConnection = try await blockManagerService.createConnection(
            from: carrierBlock.id, sourcePort: "signal",
            to: fmBlock.id, destinationPort: "carrier"
        )

        let outputConnection = try await blockManagerService.createConnection(
            from: fmBlock.id, sourcePort: "output",
            to: outputBlock.id, destinationPort: "input"
        )

        // Verify initial configuration
        let originalConfig = await blockManagerService.getCurrentConfiguration()
        XCTAssertEqual(originalConfig.blocks.count, 4)
        XCTAssertEqual(originalConfig.connections.count, 3)

        // Step 2: Save configuration with descriptive name
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        let configURL = tempDirectory.appendingPathComponent("FM_Test_Signal.json")

        try await blockManagerService.saveConfiguration(to: configURL)

        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path), "Configuration file should be created")

        // Step 3: Create different configuration to test loading
        await blockManagerService.clearConfiguration()

        // Create simple 1 kHz sine wave
        let simpleBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        try await blockManagerService.updateBlockParameter(blockId: simpleBlock.id, parameterName: "frequency", value: 1000.0)

        let simpleOutput = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 200, y: 0))

        _ = try await blockManagerService.createConnection(
            from: simpleBlock.id, sourcePort: "signal",
            to: simpleOutput.id, destinationPort: "input"
        )

        // Verify different configuration
        let differentConfig = await blockManagerService.getCurrentConfiguration()
        XCTAssertEqual(differentConfig.blocks.count, 2)
        XCTAssertEqual(differentConfig.connections.count, 1)

        let simpleFreq = differentConfig.blocks.first { $0.type == .sineOscillator }?.parameters["frequency"]?.value
        XCTAssertEqual(simpleFreq, 1000.0)

        // Step 4: Load saved configuration
        let loadedConfig = try await blockManagerService.loadConfiguration(from: configURL)

        // Step 5: Verify all blocks and connections are restored
        XCTAssertEqual(loadedConfig.blocks.count, 4)
        XCTAssertEqual(loadedConfig.connections.count, 3)

        // Verify specific blocks were restored
        let loadedCarrier = loadedConfig.blocks.first { $0.type == .sineOscillator && $0.position.x == 300 }
        let loadedTriangle = loadedConfig.blocks.first { $0.type == .triangleOscillator }
        let loadedFM = loadedConfig.blocks.first { $0.type == .frequencyModulator }
        let loadedOutput = loadedConfig.blocks.first { $0.type == .audioOutput }

        XCTAssertNotNil(loadedCarrier, "Carrier block should be restored")
        XCTAssertNotNil(loadedTriangle, "Triangle block should be restored")
        XCTAssertNotNil(loadedFM, "FM block should be restored")
        XCTAssertNotNil(loadedOutput, "Output block should be restored")

        // Step 6: Verify all parameter values are correct
        let carrierFreq = loadedCarrier?.parameters["frequency"]?.value
        XCTAssertEqual(carrierFreq, 10000.0, "Carrier frequency should be restored")

        let triangleFreq = loadedTriangle?.parameters["frequency"]?.value
        XCTAssertEqual(triangleFreq, 100.0, "Triangle frequency should be restored")

        let fmDeviation = loadedFM?.parameters["deviation"]?.value
        XCTAssertEqual(fmDeviation, 3000.0, "FM deviation should be restored")

        // Step 7: Verify connections are preserved
        let connections = loadedConfig.connections
        XCTAssertEqual(connections.count, 3)

        // Check modulation connection
        let modConnection = connections.first { conn in
            let sourceBlock = loadedConfig.blocks.first { $0.id == conn.sourceBlockId }
            return sourceBlock?.type == .triangleOscillator && conn.destinationPort == "modulation"
        }
        XCTAssertNotNil(modConnection, "Modulation connection should be restored")

        // Check carrier connection
        let carrConnection = connections.first { conn in
            let sourceBlock = loadedConfig.blocks.first { $0.id == conn.sourceBlockId }
            return sourceBlock?.type == .sineOscillator && conn.destinationPort == "carrier"
        }
        XCTAssertNotNil(carrConnection, "Carrier connection should be restored")

        // Check output connection
        let outConnection = connections.first { conn in
            let destBlock = loadedConfig.blocks.first { $0.id == conn.destinationBlockId }
            return destBlock?.type == .audioOutput
        }
        XCTAssertNotNil(outConnection, "Output connection should be restored")

        // Step 8: Verify configuration metadata
        XCTAssertEqual(loadedConfig.version, "1.0", "Version should be preserved")
        XCTAssertFalse(loadedConfig.id.uuidString.isEmpty, "Configuration should have valid ID")

        // Clean up
        try? FileManager.default.removeItem(at: configURL)

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected save/load workflow")
    }

    func testConfigurationLoad_NonExistentFile_ThrowsError() async {
        // Test error handling for non-existent configuration files

        let nonExistentURL = URL(fileURLWithPath: "/tmp/non_existent_config.json")

        do {
            _ = try await blockManagerService.loadConfiguration(from: nonExistentURL)
            XCTFail("Should throw error for non-existent file")
        } catch BlockManagerError.configurationLoadError(let message) {
            XCTAssertTrue(message.contains("file not found") || message.contains("does not exist"))
        } catch {
            XCTFail("Should throw specific ConfigurationLoadError")
        }

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected error handling")
    }

    func testConfigurationLoad_CorruptedFile_ThrowsError() async throws {
        // Test error handling for corrupted configuration files

        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        let corruptedURL = tempDirectory.appendingPathComponent("corrupted_config.json")

        // Create corrupted JSON file
        let corruptedContent = "{ invalid json content }"
        try corruptedContent.write(to: corruptedURL, atomically: true, encoding: .utf8)

        do {
            _ = try await blockManagerService.loadConfiguration(from: corruptedURL)
            XCTFail("Should throw error for corrupted file")
        } catch BlockManagerError.configurationLoadError(let message) {
            XCTAssertTrue(message.contains("parse") || message.contains("invalid") || message.contains("corrupted"))
        } catch {
            XCTFail("Should throw specific ConfigurationLoadError")
        }

        // Clean up
        try? FileManager.default.removeItem(at: corruptedURL)

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected corruption handling")
    }

    func testConfigurationSave_InvalidPath_ThrowsError() async {
        // Test error handling for invalid save paths

        // Create simple configuration first
        _ = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))

        // Attempt to save to invalid path
        let invalidURL = URL(fileURLWithPath: "/invalid/directory/config.json")

        do {
            try await blockManagerService.saveConfiguration(to: invalidURL)
            XCTFail("Should throw error for invalid save path")
        } catch BlockManagerError.configurationSaveError(let message) {
            XCTAssertTrue(message.contains("path") || message.contains("directory") || message.contains("permission"))
        } catch {
            XCTFail("Should throw specific ConfigurationSaveError")
        }

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected save error handling")
    }

    func testConfigurationVersioning_BackwardCompatibility_LoadsOlderVersions() async throws {
        // Test backward compatibility with older configuration versions

        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        let legacyURL = tempDirectory.appendingPathComponent("legacy_config.json")

        // Create legacy configuration format (version 0.9)
        let legacyConfig = """
        {
          "version": "0.9",
          "id": "legacy-config-id",
          "name": "Legacy Configuration",
          "createdDate": "2025-01-01T00:00:00Z",
          "modifiedDate": "2025-01-01T00:00:00Z",
          "blocks": [
            {
              "id": "block-1",
              "type": "sine_oscillator",
              "title": "Legacy Sine",
              "position": {"x": 100, "y": 100},
              "parameters": {
                "frequency": {
                  "name": "frequency",
                  "displayName": "Frequency",
                  "value": 440.0,
                  "minimumValue": 20.0,
                  "maximumValue": 20000.0,
                  "unit": "Hz",
                  "stepSize": 1.0,
                  "isLogarithmic": true
                }
              },
              "isActive": false
            }
          ],
          "connections": [],
          "metadata": {}
        }
        """

        try legacyConfig.write(to: legacyURL, atomically: true, encoding: .utf8)

        // Attempt to load legacy configuration
        let loadedConfig = try await blockManagerService.loadConfiguration(from: legacyURL)

        // Verify configuration is loaded with migration
        XCTAssertEqual(loadedConfig.blocks.count, 1)
        XCTAssertEqual(loadedConfig.version, "1.0") // Should be migrated to current version

        let loadedBlock = loadedConfig.blocks.first!
        XCTAssertEqual(loadedBlock.type, .sineOscillator)
        XCTAssertEqual(loadedBlock.parameters["frequency"]?.value, 440.0)

        // Clean up
        try? FileManager.default.removeItem(at: legacyURL)

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected version compatibility")
    }

    func testConfigurationPersistence_LargeConfiguration_HandlesComplexSetups() async throws {
        // Test persistence of large, complex configurations

        var blocks: [UUID] = []
        var connections: [(source: UUID, dest: UUID)] = []

        // Create a complex setup with 20+ blocks
        for i in 0..<25 {
            let blockType: BlockType = [.sineOscillator, .triangleOscillator, .amplifier, .mixer].randomElement()!
            let position = CGPoint(x: Double(i % 5) * 200, y: Double(i / 5) * 150)

            let block = try await blockManagerService.createBlock(type: blockType, at: position)
            blocks.append(block.id)

            // Set some parameters
            if blockType == .sineOscillator || blockType == .triangleOscillator {
                let frequency = Double.random(in: 100...1000)
                try await blockManagerService.updateBlockParameter(blockId: block.id, parameterName: "frequency", value: frequency)
            }
        }

        // Create many connections (avoiding feedback loops)
        for i in 0..<min(blocks.count - 1, 20) {
            let sourceId = blocks[i]
            let destId = blocks[i + 1]

            do {
                _ = try await blockManagerService.createConnection(
                    from: sourceId, sourcePort: "signal",
                    to: destId, destinationPort: "input"
                )
                connections.append((source: sourceId, dest: destId))
            } catch {
                // Ignore connection errors for this stress test
            }
        }

        // Save large configuration
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        let largeConfigURL = tempDirectory.appendingPathComponent("large_config.json")

        try await blockManagerService.saveConfiguration(to: largeConfigURL)

        // Verify file size is reasonable (should be under 1MB as per requirements)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: largeConfigURL.path)
        let fileSize = fileAttributes[.size] as! UInt64
        XCTAssertLessThan(fileSize, 1_000_000, "Large configuration should be under 1MB")

        // Clear and reload
        await blockManagerService.clearConfiguration()
        let loadedConfig = try await blockManagerService.loadConfiguration(from: largeConfigURL)

        // Verify all blocks and connections were preserved
        XCTAssertEqual(loadedConfig.blocks.count, 25)
        XCTAssertGreaterThan(loadedConfig.connections.count, 15) // Some connections may have failed due to validation

        // Verify parameter preservation in large config
        let loadedOscillators = loadedConfig.blocks.filter { $0.type == .sineOscillator || $0.type == .triangleOscillator }
        for oscillator in loadedOscillators {
            let frequency = oscillator.parameters["frequency"]?.value
            XCTAssertNotNil(frequency, "Frequency parameter should be preserved")
            XCTAssertGreaterThanOrEqual(frequency!, 100.0)
            XCTAssertLessThanOrEqual(frequency!, 1000.0)
        }

        // Clean up
        try? FileManager.default.removeItem(at: largeConfigURL)

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected large config handling")
    }

    func testConfigurationPersistence_MultipleFormats_SupportsJSONOnly() async throws {
        // Test that only JSON format is supported (as per specification)

        // Create simple configuration
        let block = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        try await blockManagerService.updateBlockParameter(blockId: block.id, parameterName: "frequency", value: 440.0)

        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())

        // Test JSON format (should work)
        let jsonURL = tempDirectory.appendingPathComponent("config.json")
        try await blockManagerService.saveConfiguration(to: jsonURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path))

        // Verify JSON content is valid
        let jsonData = try Data(contentsOf: jsonURL)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
        XCTAssertTrue(jsonObject is [String: Any], "Configuration should be valid JSON")

        if let configDict = jsonObject as? [String: Any] {
            XCTAssertEqual(configDict["version"] as? String, "1.0")
            XCTAssertNotNil(configDict["blocks"])
            XCTAssertNotNil(configDict["connections"])
        }

        // Test loading JSON
        let loadedConfig = try await blockManagerService.loadConfiguration(from: jsonURL)
        XCTAssertEqual(loadedConfig.blocks.count, 1)

        // Clean up
        try? FileManager.default.removeItem(at: jsonURL)

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected JSON format support")
    }

    func testConfigurationPersistence_ConcurrentAccess_HandlesMultipleOperations() async throws {
        // Test concurrent save/load operations

        // Create base configuration
        let block = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))

        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        var saveURLs: [URL] = []

        // Create multiple save operations concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                let url = tempDirectory.appendingPathComponent("concurrent_config_\(i).json")
                saveURLs.append(url)

                group.addTask {
                    do {
                        try await self.blockManagerService.saveConfiguration(to: url)
                    } catch {
                        // Some operations may fail due to concurrency, this is acceptable
                    }
                }
            }
        }

        // Verify at least some saves succeeded
        let successfulSaves = saveURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        XCTAssertGreaterThan(successfulSaves.count, 0, "At least one concurrent save should succeed")

        // Test concurrent loads
        var loadedConfigs: [BlockConfiguration] = []

        await withTaskGroup(of: BlockConfiguration?.self) { group in
            for url in successfulSaves {
                group.addTask {
                    do {
                        return try await self.blockManagerService.loadConfiguration(from: url)
                    } catch {
                        return nil
                    }
                }
            }

            for await config in group {
                if let config = config {
                    loadedConfigs.append(config)
                }
            }
        }

        // Verify loads were successful
        XCTAssertGreaterThan(loadedConfigs.count, 0, "At least one concurrent load should succeed")

        for config in loadedConfigs {
            XCTAssertEqual(config.blocks.count, 1)
            XCTAssertEqual(config.blocks.first?.type, .sineOscillator)
        }

        // Clean up
        for url in saveURLs {
            try? FileManager.default.removeItem(at: url)
        }

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected concurrent access handling")
    }
}