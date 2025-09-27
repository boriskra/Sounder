import XCTest
import Combine
@testable import Sounder

class AudioServiceTests: XCTestCase {

    var audioService: AudioService!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        audioService = AVFAudioService() // Use the concrete implementation
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        audioService = nil
        cancellables = nil
        super.tearDown()
    }

    func testAvailableSoundsPublisher() {
        let expectation = XCTestExpectation(description: "Available sounds received")
        audioService.availableSoundsPublisher
            .sink { sounds in
                XCTAssertNotNil(sounds)
                // Expecting an empty array or some default sounds initially
                expectation.fulfill()
            }
            .store(in: &cancellables)
        wait(for: [expectation], timeout: 1.0)
    }

    func testAvailableOutputDevicesPublisher() {
        let expectation = XCTestExpectation(description: "Available output devices received")
        audioService.availableOutputDevicesPublisher
            .sink { devices in
                XCTAssertNotNil(devices)
                // Expecting an empty array or some default devices initially
                expectation.fulfill()
            }
            .store(in: &cancellables)
        wait(for: [expectation], timeout: 1.0)
    }

    func testCurrentOutputDevice_setAndGet() {
        XCTAssertNil(audioService.currentOutputDevice)
        let device = OutputDevice(id: 1, name: "Test Device")
        audioService.currentOutputDevice = device
        XCTAssertEqual(audioService.currentOutputDevice?.id, device.id)
        XCTAssertEqual(audioService.currentOutputDevice?.name, device.name)
    }

    func testCurrentSound_setAndGet() {
        XCTAssertNil(audioService.currentSound)
        let sound = Sound(name: "Test Sound", waveform: .sine)
        audioService.currentSound = sound
        XCTAssertEqual(audioService.currentSound?.name, sound.name)
        XCTAssertEqual(audioService.currentSound?.waveform, sound.waveform)
    }

    func testPlay() {
        // This test will initially fail as AVFAudioService is not fully implemented
        let sound = Sound(name: "Test Sound", waveform: .sine)
        audioService.currentSound = sound
        XCTAssertThrowsError(try audioService.play()) { error in
            XCTAssertTrue(error is AudioServiceError, "Expected AudioServiceError")
        }
    }

    func testStop() {
        // This test will initially fail
        XCTAssertNoThrow(audioService.stop())
    }

    func testSpectrum() {
        // This test will initially fail
        let expectation = XCTestExpectation(description: "Spectrum data received")
        expectation.isInverted = true // Expect no data initially

        audioService.spectrum
            .sink { spectrumData in
                XCTAssertNotNil(spectrumData)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 1.0)
    }
}