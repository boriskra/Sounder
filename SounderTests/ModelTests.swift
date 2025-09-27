import XCTest
@testable import Sounder

class ModelTests: XCTestCase {

    func testSound() {
        let sound = Sound(name: "Sine", waveform: .sine)
        XCTAssertEqual(sound.name, "Sine")
        XCTAssertEqual(sound.waveform, .sine)
    }

    func testParameter() {
        let parameter = Parameter(name: "Frequency", value: 440.0)
        XCTAssertEqual(parameter.name, "Frequency")
        XCTAssertEqual(parameter.value, 440.0)
    }

    func testOutputDevice() {
        let device = OutputDevice(id: 1, name: "Built-in Output")
        XCTAssertEqual(device.id, 1)
        XCTAssertEqual(device.name, "Built-in Output")
    }
}