import XCTest
@testable import FinanceDemo

final class AppNavigationTests: XCTestCase {
    func testSupportedPocketLedgerRoutesSelectExpectedTabs() {
        XCTAssertEqual(
            AppTab(url: URL(string: "pocketledger://overview")!),
            .overview
        )
        XCTAssertEqual(
            AppTab(url: URL(string: "pocketledger://transactions")!),
            .transactions
        )
    }

    func testExternalAndUnknownRoutesAreIgnored() {
        XCTAssertNil(AppTab(url: URL(string: "https://example.com")!))
        XCTAssertNil(AppTab(url: URL(string: "pocketledger://metrics")!))
    }
}
