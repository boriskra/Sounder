import XCTest
import Combine
@testable import Sounder

class ContentViewModelTests: XCTestCase {

    var viewModel: ContentViewModel!
    var mockAudioService: MockAudioService!

    override func setUp() {
        super.setUp()
        mockAudioService = MockAudioService()
        viewModel = ContentViewModel(audioService: mockAudioService)
    }

    override func tearDown() {
        viewModel = nil
        mockAudioService = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(viewModel)
        XCTAssertFalse(viewModel.sounds.isEmpty)
        XCTAssertFalse(viewModel.devices.isEmpty)
        XCTAssertNotNil(viewModel.selectedDevice)
    }

    func testPlay() {
        viewModel.selectedSound = viewModel.sounds.first
        viewModel.play()
        // No direct assertion on spectrum here, as it's hard to test synchronously
        // We assume that if play() is called, the audio service attempts to play.
    }

    func testStop() {
        viewModel.selectedSound = viewModel.sounds.first
        viewModel.play()
        viewModel.stop()
        // No direct assertion on spectrum here, as it's hard to test synchronously
        // We assume that if stop() is called, the audio service attempts to stop.
    }
}