import XCTest

final class FinanceDemoUITests: XCTestCase {
    func testSetupCanBeSkippedAndAddActionRemainsReachable() {
        let app = XCUIApplication()
        app.launch()

        let skipButton = app.buttons["Skip for now"]
        if skipButton.waitForExistence(timeout: 5) {
            skipButton.tap()
        }

        let addButton = app.buttons["Add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))

        addButton.tap()
        XCTAssertTrue(app.buttons["Expense"].waitForExistence(timeout: 2))
    }

    func testNativeTabBarIsPresented() {
        let app = XCUIApplication()
        app.launch()

        let skipButton = app.buttons["Skip for now"]
        if skipButton.waitForExistence(timeout: 5) {
            skipButton.tap()
        }

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["Overview"].waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["More"].waitForExistence(timeout: 5))
    }
}
