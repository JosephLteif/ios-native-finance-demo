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

        tabBar.buttons["More"].tap()
        XCTAssertTrue(app.buttons["Transactions"].waitForExistence(timeout: 5))

        app.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["Expense"].waitForExistence(timeout: 5))
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
