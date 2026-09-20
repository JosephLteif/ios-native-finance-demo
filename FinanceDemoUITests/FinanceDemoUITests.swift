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
        let addButton = app.buttons["Add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        XCTAssertFalse(tabBar.buttons["Add"].exists)
        XCTAssertFalse(tabBar.buttons["Transactions"].exists)
        let moreButton = tabBar.buttons["More"]
        XCTAssertTrue(moreButton.exists)
        XCTAssertLessThan(moreButton.frame.maxX, addButton.frame.minX)
        XCTAssertLessThan(abs(tabBar.frame.midY - addButton.frame.midY), 4)

        tabBar.buttons["More"].tap()
        XCTAssertTrue(app.buttons["Transactions"].waitForExistence(timeout: 5))

        app.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["Expense"].waitForExistence(timeout: 5))
    }

    func testMetricsPeriodSwitchingKeepsPeriodControlsResponsive() {
        let app = XCUIApplication()
        app.launch()

        let skipButton = app.buttons["Skip for now"]
        if skipButton.waitForExistence(timeout: 5) {
            skipButton.tap()
        }

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.buttons["Metrics"].waitForExistence(timeout: 5))
        tabBar.buttons["Metrics"].tap()

        XCTAssertTrue(app.staticTexts["metrics-period-title"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.buttons["Year"].waitForExistence(timeout: 5))
        app.buttons["Year"].tap()
        XCTAssertTrue(app.staticTexts["metrics-period-title"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.buttons["Month"].waitForExistence(timeout: 5))
        app.buttons["Month"].tap()
        XCTAssertTrue(app.buttons["Previous period"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Next period"].waitForExistence(timeout: 5))
    }

    func testTransactionsExposeSelectionAndSavedFilters() {
        let app = XCUIApplication()
        app.launch()

        let skipButton = app.buttons["Skip for now"]
        if skipButton.waitForExistence(timeout: 5) {
            skipButton.tap()
        }

        app.tabBars.firstMatch.buttons["More"].tap()
        app.buttons["Transactions"].tap()

        XCTAssertTrue(app.buttons["select-transactions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["transaction-saved-filter"].waitForExistence(timeout: 5))

        app.buttons["select-transactions"].tap()
        XCTAssertTrue(app.otherElements["transaction-selection-toolbar"].waitForExistence(timeout: 5))
    }

    func testImportWizardStepsBulkArchiveExceptionsAndFinalConfirmation() {
        let app = XCUIApplication()
        app.launchArguments.append("-ImportWizardUITest")
        app.launch()

        XCTAssertTrue(app.otherElements["importWizard"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["importWizard.next"].waitForExistence(timeout: 5))

        app.buttons["importWizard.next"].tap()
        XCTAssertTrue(app.staticTexts["Defaults"].waitForExistence(timeout: 5))

        app.buttons["importWizard.next"].tap()
        XCTAssertTrue(app.buttons["importWizard.accountSelect"].waitForExistence(timeout: 20))

        app.buttons["importWizard.accountSelect"].tap()
        let goldRow = app.buttons["importWizard.accountRow.gold"]
        XCTAssertTrue(goldRow.waitForExistence(timeout: 5))
        goldRow.tap()
        app.buttons["importWizard.bulkAccounts"].tap()
        XCTAssertTrue(app.buttons["Archive"].waitForExistence(timeout: 5))
        app.buttons["Archive"].tap()
        XCTAssertTrue(app.buttons["Apply"].waitForExistence(timeout: 5))
        app.buttons["Apply"].tap()

        app.buttons["importWizard.next"].tap()
        XCTAssertTrue(app.buttons["Exceptions first"].waitForExistence(timeout: 5))
        app.buttons["All rows"].tap()
        app.buttons["Exceptions first"].tap()

        app.buttons["importWizard.import"].tap()
        XCTAssertTrue(app.buttons["Import"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
    }
}
