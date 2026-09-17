import XCTest

final class FinanceDemoUITests: XCTestCase {
    func testSetupCanBeSkippedAndAddActionRemainsReachable() {
        let app = XCUIApplication()
        app.launch()

        let skipButton = app.buttons["Skip for now"]
        if skipButton.waitForExistence(timeout: 5) {
            skipButton.tap()
        }

        let addAction = app.buttons["add-transaction-button"]
        let nativeAddButton = app.buttons["Add"]
        XCTAssertTrue(
            addAction.waitForExistence(timeout: 1) ||
                nativeAddButton.waitForExistence(timeout: 5)
        )
    }
}
