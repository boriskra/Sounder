import XCTest

class SounderFeatureTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Play"].exists)
        XCTAssertTrue(app.staticTexts["Stop"].exists)
    }

    func testPlayAndStop() throws {
        let app = XCUIApplication()
        app.launch()

        let playButton = app.buttons["Play"]
        let stopButton = app.buttons["Stop"]

        // Select a sound
        app.tables.buttons.firstMatch.click()

        playButton.click()
        // Add a delay to allow the spectrum to be updated
        sleep(1)
        stopButton.click()
    }
}