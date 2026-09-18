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

    func testCustomTabBarUsesAccessibleSelectionAndKeepsAddReachable() {
        let app = XCUIApplication()
        app.launch()

        let skipButton = app.buttons["Skip for now"]
        if skipButton.waitForExistence(timeout: 5) {
            skipButton.tap()
        }

        XCTAssertEqual(app.tabBars.count, 0)

        let overview = app.buttons["tab-overview"]
        let transactions = app.buttons["tab-transactions"]
        let metrics = app.buttons["tab-metrics"]
        let more = app.buttons["tab-more"]

        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        XCTAssertTrue(transactions.waitForExistence(timeout: 5))
        XCTAssertTrue(metrics.waitForExistence(timeout: 5))
        XCTAssertTrue(more.waitForExistence(timeout: 5))

        transactions.tap()
        XCTAssertEqual(transactions.value as? String, "Selected")

        let addAction = app.buttons["add-transaction-button"]
        XCTAssertTrue(addAction.exists)
        XCTAssertTrue(addAction.isHittable)
    }
}
