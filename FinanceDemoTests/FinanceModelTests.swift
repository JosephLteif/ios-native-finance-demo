import XCTest
@testable import FinanceDemo

final class FinanceModelTests: XCTestCase {
    func testMoneyParsingUsesCurrencyMinorUnits() {
        XCTAssertEqual(
            Money.parse("12.50", currency: .usd),
            .some(Money(currency: .usd, minorUnits: 1_250))
        )
        XCTAssertEqual(
            Money.parse("125000", currency: .lbp),
            .some(Money(currency: .lbp, minorUnits: 125_000))
        )
    }

    func testRolloverCarriesUnusedPriorMonthAllowance() {
        let calendar = Calendar(identifier: .gregorian)
        let currentMonth = calendar.dateInterval(of: .month, for: .now)!
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth.start)!
        let category = LedgerCategory(name: "Food")
        let account = Account(
            name: "Cash",
            type: .cash,
            currency: .lbp,
            openingBalance: Money(currency: .lbp, minorUnits: 10_000)
        )
        let transaction = LedgerTransaction(
            date: calendar.date(byAdding: .day, value: 5, to: previousMonth)!,
            note: "Lunch",
            kind: .expense,
            categoryID: category.id,
            outflows: [
                MoneyMovement(
                    accountID: account.id,
                    money: Money(currency: .lbp, minorUnits: 300)
                )
            ],
            inflows: []
        )
        let data = FinanceData(
            accounts: [account],
            categories: [category],
            transactions: [transaction]
        )
        let budget = LedgerBudget(
            categoryID: category.id,
            currency: .lbp,
            monthlyLimit: Money(currency: .lbp, minorUnits: 1_000),
            rollover: true,
            startedAt: previousMonth
        )

        XCTAssertEqual(
            financeBudgetSpent(budget, in: data, interval: currentMonth).minorUnits,
            0
        )
        XCTAssertEqual(
            financeBudgetAllowance(budget, in: data, interval: currentMonth).minorUnits,
            1_700
        )
    }

    func testNonRolloverBudgetKeepsMonthlyLimit() {
        let category = LedgerCategory(name: "Food")
        let budget = LedgerBudget(
            categoryID: category.id,
            currency: .usd,
            monthlyLimit: Money(currency: .usd, minorUnits: 500),
            rollover: false
        )
        let data = FinanceData(
            accounts: [],
            categories: [category],
            transactions: []
        )

        XCTAssertEqual(
            financeBudgetAllowance(budget, in: data).minorUnits,
            500
        )
    }

    func testMonthlyScheduleAdvancesByOneMonth() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let next = ScheduleFrequency.monthly.nextDate(
            after: date,
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertEqual(
            next,
            Calendar(identifier: .gregorian).date(byAdding: .month, value: 1, to: date)
        )
    }

    func testTemplateCreatesFreshTransactionAndMovementIDs() {
        let account = Account(
            name: "Cash",
            type: .cash,
            currency: .usd,
            openingBalance: Money(currency: .usd, minorUnits: 0)
        )
        let transaction = LedgerTransaction(
            note: "Coffee",
            kind: .expense,
            categoryID: nil,
            outflows: [
                MoneyMovement(
                    accountID: account.id,
                    money: Money(currency: .usd, minorUnits: 500)
                )
            ],
            inflows: []
        )
        let template = LedgerTemplate(name: "Coffee", transaction: transaction)
        let copy = template.transactionTemplate

        XCTAssertNotEqual(copy.id, transaction.id)
        XCTAssertNotEqual(copy.outflows.first?.id, transaction.outflows.first?.id)
        XCTAssertEqual(copy.outflows.first?.accountID, account.id)
        XCTAssertEqual(copy.outflows.first?.money, transaction.outflows.first?.money)
    }
}
