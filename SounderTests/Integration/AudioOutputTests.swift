import XCTest
import AVFoundation
@testable import Sounder

/// Integration tests for Bluetooth audio output routing
/// Tests the requirement for routing to Bluetooth devices without affecting system audio
class AudioOutputTests: XCTestCase {

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

    // MARK: - Test Scenario 3: Bluetooth Audio Output (from quickstart.md)

    func testBluetoothOutput_DeviceSelection_RoutesToSpecificDevice() async throws {
        // Test Scenario 3 from quickstart.md: Bluetooth Audio Output

        // Step 1: Get available output devices
        let availableDevices = await audioBlockService.getAvailableOutputDevices()
        XCTAssertFalse(availableDevices.isEmpty, "Should have at least one output device")

        // Verify default device exists
        let defaultDevice = availableDevices.first { $0.isDefault }
        XCTAssertNotNil(defaultDevice, "Should have a default output device")

        // Look for Bluetooth devices (simulated for testing)
        let bluetoothDevices = availableDevices.filter { $0.name.contains("Bluetooth") || $0.name.contains("AirPods") }

        // Skip if no Bluetooth devices available (common in CI)
        guard !bluetoothDevices.isEmpty else {
            XCTSkip("No Bluetooth devices available for testing")
        }

        let bluetoothDevice = bluetoothDevices.first!

        // Step 2: Create test signal chain
        let sineBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        try await blockManagerService.updateBlockParameter(blockId: sineBlock.id, parameterName: "frequency", value: 1000.0)

        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 200, y: 0))

        _ = try await blockManagerService.createConnection(
            from: sineBlock.id, sourcePort: "signal",
            to: outputBlock.id, destinationPort: "input"
        )

        // Step 3: Initialize audio engine with default device
        try await audioBlockService.initializeAudioEngine(sampleRate: 48000, bufferSize: 512)

        // Verify initial device (should be default)
        let initialDevice = await audioBlockService.getCurrentOutputDevice()
        XCTAssertEqual(initialDevice?.isDefault, true)

        // Step 4: Select Bluetooth device
        try await audioBlockService.setOutputDevice(bluetoothDevice)

        // Verify device selection
        let selectedDevice = await audioBlockService.getCurrentOutputDevice()
        XCTAssertEqual(selectedDevice?.id, bluetoothDevice.id)
        XCTAssertEqual(selectedDevice?.name, bluetoothDevice.name)

        // Step 5: Test audio routing to Bluetooth device
        try await audioBlockService.registerBlock(sineBlock)
        try await audioBlockService.registerBlock(outputBlock)

        try await audioBlockService.connectBlocks(
            from: sineBlock.id, sourcePort: "signal",
            to: outputBlock.id, destinationPort: "input"
        )

        try await audioBlockService.startEngine()

        // Verify audio is being generated
        let isEngineRunning = await audioBlockService.isEngineRunning()
        XCTAssertTrue(isEngineRunning, "Audio engine should be running")

        // Test that audio routing is isolated (system audio should be unaffected)
        // This would typically require system-level testing, but we can verify device isolation
        let currentDevice = await audioBlockService.getCurrentOutputDevice()
        XCTAssertEqual(currentDevice?.id, bluetoothDevice.id, "Audio should be routed to selected Bluetooth device")

        await audioBlockService.stopEngine()

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected Bluetooth routing")
    }

    func testAudioOutput_DeviceEnumeration_IncludesAllSystemDevices() async {
        // Test comprehensive device enumeration

        let devices = await audioBlockService.getAvailableOutputDevices()

        // Verify basic device properties
        for device in devices {
            XCTAssertFalse(device.id.isEmpty, "Device ID should not be empty")
            XCTAssertFalse(device.name.isEmpty, "Device name should not be empty")

            // At least one device should be available
            if device.isDefault {
                XCTAssertTrue(device.isAvailable, "Default device should be available")
            }
        }

        // Should have at least one default device
        let defaultDevices = devices.filter { $0.isDefault }
        XCTAssertEqual(defaultDevices.count, 1, "Should have exactly one default device")

        // Test device categorization
        let availableDevices = devices.filter { $0.isAvailable }
        XCTAssertFalse(availableDevices.isEmpty, "Should have at least one available device")

        // Log devices for debugging (would be visible in test output)
        for device in devices {
            print("Device: \(device.name), ID: \(device.id), Default: \(device.isDefault), Available: \(device.isAvailable)")
        }

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected device enumeration")
    }

    func testAudioOutput_DeviceSwitching_ChangesDuringPlayback() async throws {
        // Test switching output devices during active audio playback

        let devices = await audioBlockService.getAvailableOutputDevices()
        guard devices.count >= 2 else {
            XCTSkip("Need at least 2 output devices for switching test")
        }

        let device1 = devices[0]
        let device2 = devices[1]

        // Create test signal
        let sineBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        try await blockManagerService.updateBlockParameter(blockId: sineBlock.id, parameterName: "frequency", value: 440.0)

        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 200, y: 0))

        _ = try await blockManagerService.createConnection(
            from: sineBlock.id, sourcePort: "signal",
            to: outputBlock.id, destinationPort: "input"
        )

        // Initialize with first device
        try await audioBlockService.initializeAudioEngine(sampleRate: 48000, bufferSize: 512)
        try await audioBlockService.setOutputDevice(device1)

        try await audioBlockService.registerBlock(sineBlock)
        try await audioBlockService.registerBlock(outputBlock)

        try await audioBlockService.connectBlocks(
            from: sineBlock.id, sourcePort: "signal",
            to: outputBlock.id, destinationPort: "input"
        )

        try await audioBlockService.startEngine()

        // Verify initial device
        let initialDevice = await audioBlockService.getCurrentOutputDevice()
        XCTAssertEqual(initialDevice?.id, device1.id)

        // Switch to second device during playback
        try await audioBlockService.setOutputDevice(device2)

        // Verify device was switched
        let switchedDevice = await audioBlockService.getCurrentOutputDevice()
        XCTAssertEqual(switchedDevice?.id, device2.id)

        // Verify audio continues without interruption
        let bufferUnderruns = await audioBlockService.getBufferUnderrunCount()
        XCTAssertEqual(bufferUnderruns, 0, "Device switching should not cause buffer underruns")

        let isStillRunning = await audioBlockService.isEngineRunning()
        XCTAssertTrue(isStillRunning, "Audio engine should continue running after device switch")

        // Switch back to first device
        try await audioBlockService.setOutputDevice(device1)

        let finalDevice = await audioBlockService.getCurrentOutputDevice()
        XCTAssertEqual(finalDevice?.id, device1.id)

        await audioBlockService.stopEngine()

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected device switching")
    }

    func testAudioOutput_InvalidDevice_ThrowsError() async throws {
        // Test error handling for invalid devices

        let invalidDevice = OutputDevice(
            id: "invalid-device-12345",
            name: "Non-existent Audio Device",
            isDefault: false,
            isAvailable: false
        )

        // Attempt to set invalid device
        do {
            try await audioBlockService.setOutputDevice(invalidDevice)
            XCTFail("Should throw error for invalid device")
        } catch AudioBlockError.audioDeviceError(let message) {
            XCTAssertTrue(message.contains("invalid") || message.contains("not available") || message.contains("not found"))
        } catch {
            XCTFail("Should throw specific AudioDeviceError")
        }

        // Verify current device is unchanged
        let currentDevice = await audioBlockService.getCurrentOutputDevice()
        XCTAssertNotEqual(currentDevice?.id, invalidDevice.id)

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected error handling")
    }

    func testAudioOutput_SystemAudioIsolation_DoesNotAffectOtherApps() async throws {
        // Test that Sounder audio routing doesn't affect system audio from other apps

        // This test simulates the isolation behavior described in quickstart.md
        // In practice, this would require coordination with system audio or other apps

        let devices = await audioBlockService.getAvailableOutputDevices()
        let defaultDevice = devices.first { $0.isDefault }!

        // Find a non-default device for Sounder
        let alternateDevice = devices.first { !$0.isDefault && $0.isAvailable }
        guard let sounderDevice = alternateDevice else {
            XCTSkip("Need alternate device for isolation testing")
        }

        // Create test signal in Sounder
        let sineBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        try await blockManagerService.updateBlockParameter(blockId: sineBlock.id, parameterName: "frequency", value: 1000.0)

        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 200, y: 0))

        _ = try await blockManagerService.createConnection(
            from: sineBlock.id, sourcePort: "signal",
            to: outputBlock.id, destinationPort: "input"
        )

        // Initialize Sounder with alternate device
        try await audioBlockService.initializeAudioEngine(sampleRate: 48000, bufferSize: 512)
        try await audioBlockService.setOutputDevice(sounderDevice)

        try await audioBlockService.registerBlock(sineBlock)
        try await audioBlockService.registerBlock(outputBlock)

        try await audioBlockService.connectBlocks(
            from: sineBlock.id, sourcePort: "signal",
            to: outputBlock.id, destinationPort: "input"
        )

        try await audioBlockService.startEngine()

        // Verify Sounder audio is routed to specific device
        let sounderCurrentDevice = await audioBlockService.getCurrentOutputDevice()
        XCTAssertEqual(sounderCurrentDevice?.id, sounderDevice.id)

        // Simulate system audio check (in practice, would verify other apps still use default)
        // For testing, we verify that Sounder doesn't affect global audio settings

        // Check that engine initialization is isolated
        let audioSession = AVAudioSession.sharedInstance()
        let systemCategory = audioSession.category

        // Sounder should use its own audio routing without changing system category
        XCTAssertTrue([AVAudioSession.Category.playback, AVAudioSession.Category.playAndRecord, AVAudioSession.Category.ambient].contains(systemCategory),
                      "System audio category should remain appropriate for other apps")

        await audioBlockService.stopEngine()

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected system isolation")
    }

    func testAudioOutput_BluetoothLatency_MeetsPerformanceRequirements() async throws {
        // Test audio latency with Bluetooth devices meets performance requirements

        let devices = await audioBlockService.getAvailableOutputDevices()
        let bluetoothDevices = devices.filter { $0.name.contains("Bluetooth") || $0.name.contains("AirPods") }

        guard !bluetoothDevices.isEmpty else {
            XCTSkip("No Bluetooth devices available for latency testing")
        }

        let bluetoothDevice = bluetoothDevices.first!

        // Create test signal
        let sineBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        try await blockManagerService.updateBlockParameter(blockId: sineBlock.id, parameterName: "frequency", value: 440.0)

        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 200, y: 0))

        _ = try await blockManagerService.createConnection(
            from: sineBlock.id, sourcePort: "signal",
            to: outputBlock.id, destinationPort: "input"
        )

        // Initialize with Bluetooth device
        try await audioBlockService.initializeAudioEngine(sampleRate: 48000, bufferSize: 512)
        try await audioBlockService.setOutputDevice(bluetoothDevice)

        try await audioBlockService.registerBlock(sineBlock)
        try await audioBlockService.registerBlock(outputBlock)

        try await audioBlockService.connectBlocks(
            from: sineBlock.id, sourcePort: "signal",
            to: outputBlock.id, destinationPort: "input"
        )

        try await audioBlockService.startEngine()

        // Test latency requirements
        let audioLatency = await audioBlockService.getAudioLatency()

        // Bluetooth typically has higher latency, but should still be reasonable
        XCTAssertLessThan(audioLatency, 150.0, "Bluetooth audio latency should be under 150ms")
        XCTAssertGreaterThan(audioLatency, 0.0, "Latency should be measurable")

        // Test parameter update latency (should still meet <10ms requirement)
        let startTime = CFAbsoluteTimeGetCurrent()

        try await audioBlockService.updateBlockParameter(
            blockId: sineBlock.id,
            parameterName: "frequency",
            value: 880.0
        )

        let updateLatency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000 // Convert to ms
        XCTAssertLessThan(updateLatency, 10.0, "Parameter updates should complete within 10ms even with Bluetooth")

        // Verify no buffer underruns with Bluetooth
        let bufferUnderruns = await audioBlockService.getBufferUnderrunCount()
        XCTAssertEqual(bufferUnderruns, 0, "Bluetooth output should not cause buffer underruns")

        await audioBlockService.stopEngine()

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected Bluetooth performance")
    }

    func testAudioOutput_DeviceDisconnection_HandlesGracefully() async throws {
        // Test graceful handling of device disconnection during playback

        let devices = await audioBlockService.getAvailableOutputDevices()
        guard devices.count >= 2 else {
            XCTSkip("Need multiple devices for disconnection testing")
        }

        let primaryDevice = devices.first { $0.isAvailable }!
        let fallbackDevice = devices.first { $0.isDefault }!

        // Create test signal
        let sineBlock = try await blockManagerService.createBlock(type: .sineOscillator, at: CGPoint(x: 0, y: 0))
        let outputBlock = try await blockManagerService.createBlock(type: .audioOutput, at: CGPoint(x: 200, y: 0))

        _ = try await blockManagerService.createConnection(
            from: sineBlock.id, sourcePort: "signal",
            to: outputBlock.id, destinationPort: "input"
        )

        // Initialize with primary device
        try await audioBlockService.initializeAudioEngine(sampleRate: 48000, bufferSize: 512)
        try await audioBlockService.setOutputDevice(primaryDevice)

        try await audioBlockService.registerBlock(sineBlock)
        try await audioBlockService.registerBlock(outputBlock)

        try await audioBlockService.connectBlocks(
            from: sineBlock.id, sourcePort: "signal",
            to: outputBlock.id, destinationPort: "input"
        )

        try await audioBlockService.startEngine()

        // Simulate device disconnection by marking device as unavailable
        // In practice, this would be triggered by system events
        let unavailableDevice = OutputDevice(
            id: primaryDevice.id,
            name: primaryDevice.name,
            isDefault: primaryDevice.isDefault,
            isAvailable: false
        )

        // Attempt to continue using disconnected device should gracefully fallback
        do {
            try await audioBlockService.setOutputDevice(unavailableDevice)
            XCTFail("Should not allow setting unavailable device")
        } catch AudioBlockError.audioDeviceError {
            // Expected behavior - should reject unavailable device
        }

        // System should automatically fallback to default device or handle gracefully
        let currentDevice = await audioBlockService.getCurrentOutputDevice()
        XCTAssertTrue(currentDevice?.isAvailable ?? false, "Current device should remain available")

        // Audio should continue playing
        let isStillRunning = await audioBlockService.isEngineRunning()
        XCTAssertTrue(isStillRunning, "Audio should continue despite device change")

        await audioBlockService.stopEngine()

        // This test will fail until implementations exist
        XCTFail("Service implementations not available - test defines expected disconnection handling")
    }
}