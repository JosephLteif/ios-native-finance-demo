import XCTest
@testable import FinanceDemo

final class FinanceModelTests: XCTestCase {
    func testMetricsReportWritesExistingShareablePDF() throws {
        let report = MetricsReportData(
            periodTitle: "September 2026",
            dateRange: "Sep 1, 2026 – Sep 30, 2026",
            currency: .usd,
            categoryScope: "All categories",
            income: Money(currency: .usd, minorUnits: 0),
            expenses: Money(currency: .usd, minorUnits: 0),
            entryCount: 0,
            activityCounts: [:],
            categories: [],
            generatedAt: .now
        )

        let url = try MetricsReportPDF.writeShareableFile(for: report)
        defer { try? FileManager.default.removeItem(at: url) }

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
        XCTAssertFalse(isDirectory.boolValue)
        XCTAssertFalse(url.lastPathComponent.contains("/"))
        XCTAssertEqual(url.pathExtension, "pdf")
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 0)
    }

    func testLegacyModelFieldsDecodeToSafeDefaults() throws {
        let account = Account(
            name: "Cash",
            type: .cash,
            currency: .usd,
            openingBalance: Money(currency: .usd, minorUnits: 0)
        )
        let category = LedgerCategory(name: "Food")
        let transaction = LedgerTransaction(
            note: "Coffee",
            kind: .expense,
            categoryID: category.id,
            outflows: [
                MoneyMovement(
                    accountID: account.id,
                    money: Money(currency: .usd, minorUnits: 500)
                )
            ],
            inflows: []
        )
        let encoded = try JSONEncoder().encode(
            FinanceData(accounts: [account], categories: [category], transactions: [transaction])
        )
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "attachments")
        var accounts = try XCTUnwrap(object["accounts"] as? [[String: Any]])
        accounts[0].removeValue(forKey: "isArchived")
        object["accounts"] = accounts
        var categories = try XCTUnwrap(object["categories"] as? [[String: Any]])
        categories[0].removeValue(forKey: "isArchived")
        object["categories"] = categories
        var transactions = try XCTUnwrap(object["transactions"] as? [[String: Any]])
        transactions[0].removeValue(forKey: "attachmentIDs")
        object["transactions"] = transactions

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(FinanceData.self, from: legacyData)

        XCTAssertFalse(decoded.accounts[0].isArchived)
        XCTAssertFalse(decoded.categories[0].isArchived)
        XCTAssertEqual(decoded.transactions[0].attachmentIDs, [])
        XCTAssertEqual(decoded.attachments, [])
    }

    func testSameCurrencyTransferMustBalance() {
        let account = Account(
            name: "Cash",
            type: .cash,
            currency: .usd,
            openingBalance: Money(currency: .usd, minorUnits: 0)
        )
        let destination = Account(
            name: "Bank",
            type: .bankAccount,
            currency: .usd,
            openingBalance: Money(currency: .usd, minorUnits: 0)
        )
        let transaction = LedgerTransaction(
            note: "Unbalanced",
            kind: .transfer,
            categoryID: nil,
            outflows: [MoneyMovement(accountID: account.id, money: Money(currency: .usd, minorUnits: 100))],
            inflows: [MoneyMovement(accountID: destination.id, money: Money(currency: .usd, minorUnits: 90))]
        )
        let data = FinanceData(accounts: [account, destination], categories: [], transactions: [])

        XCTAssertEqual(
            FinanceTransactionValidator.validate(transaction, in: data),
            .unbalancedTransfer
        )
    }

    func testArchivedAccountsCannotBeUsedForNewTransactions() {
        let account = Account(
            name: "Old cash",
            type: .cash,
            currency: .usd,
            openingBalance: Money(currency: .usd, minorUnits: 0),
            isArchived: true
        )
        let transaction = LedgerTransaction(
            note: "Expense",
            kind: .expense,
            categoryID: nil,
            outflows: [MoneyMovement(accountID: account.id, money: Money(currency: .usd, minorUnits: 100))],
            inflows: []
        )
        let data = FinanceData(accounts: [account], categories: [], transactions: [])

        XCTAssertEqual(
            FinanceTransactionValidator.validate(transaction, in: data),
            .archivedMovementAccount
        )
    }

    func testMissingAttachmentReferenceIsRejected() {
        let account = Account(
            name: "Cash",
            type: .cash,
            currency: .usd,
            openingBalance: Money(currency: .usd, minorUnits: 0)
        )
        let transaction = LedgerTransaction(
            note: "Receipt",
            kind: .expense,
            categoryID: nil,
            outflows: [
                MoneyMovement(
                    accountID: account.id,
                    money: Money(currency: .usd, minorUnits: 100)
                )
            ],
            inflows: [],
            attachmentIDs: [UUID()]
        )
        let data = FinanceData(accounts: [account], categories: [], transactions: [])

        XCTAssertEqual(
            FinanceTransactionValidator.validate(transaction, in: data),
            .missingAttachment
        )
    }

    func testExpenseSpendingSubtractsReturnedMoney() {
        let category = LedgerCategory(name: "Food")
        let account = Account(
            name: "Cash",
            type: .cash,
            currency: .usd,
            openingBalance: Money(currency: .usd, minorUnits: 5_000)
        )
        let transaction = LedgerTransaction(
            note: "Lunch",
            kind: .expense,
            categoryID: category.id,
            outflows: [
                MoneyMovement(
                    accountID: account.id,
                    money: Money(currency: .usd, minorUnits: 2_000)
                )
            ],
            inflows: [
                MoneyMovement(
                    accountID: account.id,
                    money: Money(currency: .usd, minorUnits: 500)
                )
            ]
        )
        let data = FinanceData(
            accounts: [account],
            categories: [category],
            transactions: [transaction]
        )

        XCTAssertEqual(
            financeNetExpenseAmount(transaction, currency: .usd, in: data),
            1_500
        )
        let budget = LedgerBudget(
            categoryID: category.id,
            currency: .usd,
            monthlyLimit: Money(currency: .usd, minorUnits: 5_000)
        )
        XCTAssertEqual(financeBudgetSpent(budget, in: data).minorUnits, 1_500)
    }

    func testBackupBundleRoundTripsAttachmentBytes() throws {
        let attachment = LedgerAttachment(
            fileName: "receipt.jpg",
            contentType: "image/jpeg",
            relativePath: "receipt-id.jpg"
        )
        let data = FinanceData(
            accounts: [],
            categories: [],
            transactions: [],
            attachments: [attachment]
        )
        let bytes = Data([0x01, 0x02, 0x03])

        let encoded = try LedgerBackupCodec.encodeBundle(
            data,
            attachmentData: [attachment.id: bytes]
        )
        let decoded = try LedgerBackupCodec.decodeBundle(encoded)

        let decodedAttachment = try XCTUnwrap(decoded.data.attachments.first)
        XCTAssertEqual(decodedAttachment.id, attachment.id)
        XCTAssertEqual(decodedAttachment.fileName, attachment.fileName)
        XCTAssertEqual(decodedAttachment.contentType, attachment.contentType)
        XCTAssertEqual(decodedAttachment.relativePath, attachment.relativePath)
        XCTAssertEqual(decoded.attachments.first?.data, bytes)
    }

    func testUnsupportedBackupBundleVersionIsRejected() throws {
        let encoded = try LedgerBackupCodec.encodeBundle(
            FinanceData(accounts: [], categories: [], transactions: []),
            attachmentData: [:]
        )
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["version"] = 99
        let unsupported = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try LedgerBackupCodec.decodeBundle(unsupported))
        XCTAssertThrowsError(try LedgerBackupCodec.decodeBundle(Data("not a backup".utf8)))
    }

    func testMoneyParsingUsesCurrencyMinorUnits() {
        XCTAssertEqual(
            Money.parse("12.50", currency: .usd, locale: Locale(identifier: "en_US_POSIX")),
            .some(Money(currency: .usd, minorUnits: 1_250))
        )
        XCTAssertEqual(
            Money.parse("125000", currency: .lbp, locale: Locale(identifier: "en_US_POSIX")),
            .some(Money(currency: .lbp, minorUnits: 125_000))
        )
    }

    func testMoneyDisplayFormattingIsLocaleAwareAndExportsRemainStable() {
        let money = Money(currency: .usd, minorUnits: 1_250)

        XCTAssertTrue(
            money.formatted(locale: Locale(identifier: "en_US_POSIX")).contains("12.50")
        )
        XCTAssertTrue(
            money.formatted(locale: Locale(identifier: "de_DE")).contains(",50")
        )
        XCTAssertEqual(money.stableFormatted, "$12.50")
        XCTAssertEqual(
            Money.parse("1.234,50", currency: .usd, locale: Locale(identifier: "de_DE")),
            Money(currency: .usd, minorUnits: 123_450)
        )
    }

    func testImportReviewDropsUnusedCreatedRecordsAndKeepsCategoryAncestors() {
        let usedAccount = Account(
            name: "Imported cash",
            type: .cash,
            currency: .usd,
            openingBalance: Money(currency: .usd, minorUnits: 0)
        )
        let unusedAccount = Account(
            name: "Unused account",
            type: .cash,
            currency: .usd,
            openingBalance: Money(currency: .usd, minorUnits: 0)
        )
        let root = LedgerCategory(name: "Living")
        let child = LedgerCategory(name: "Food", parentID: root.id)
        let unusedCategory = LedgerCategory(name: "Unused")
        let transaction = LedgerTransaction(
            note: "Lunch",
            kind: .expense,
            categoryID: child.id,
            outflows: [
                MoneyMovement(
                    accountID: usedAccount.id,
                    money: Money(currency: .usd, minorUnits: 500)
                )
            ],
            inflows: []
        )

        let prepared = FinanceImportReview.removingUnusedCreatedRecords(
            from: FinanceData(
                accounts: [usedAccount, unusedAccount],
                categories: [root, child, unusedCategory],
                transactions: [transaction]
            )
        )

        XCTAssertEqual(prepared.accounts.map(\.id), [usedAccount.id])
        XCTAssertEqual(Set(prepared.categories.map(\.id)), Set([root.id, child.id]))
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

    func testRolloverCarryIsConsumedByLaterOverspending() {
        let calendar = Calendar(identifier: .gregorian)
        let currentMonth = calendar.dateInterval(of: .month, for: .now)!
        let january = calendar.date(byAdding: .month, value: -2, to: currentMonth.start)!
        let february = calendar.date(byAdding: .month, value: -1, to: currentMonth.start)!
        let category = LedgerCategory(name: "Food")
        let account = Account(
            name: "Cash",
            type: .cash,
            currency: .usd,
            openingBalance: Money(currency: .usd, minorUnits: 10_000)
        )
        let transactions = [
            LedgerTransaction(
                date: calendar.date(byAdding: .day, value: 5, to: january)!,
                note: "January lunch",
                kind: .expense,
                categoryID: category.id,
                outflows: [
                    MoneyMovement(
                        accountID: account.id,
                        money: Money(currency: .usd, minorUnits: 500)
                    )
                ],
                inflows: []
            ),
            LedgerTransaction(
                date: calendar.date(byAdding: .day, value: 5, to: february)!,
                note: "February lunch",
                kind: .expense,
                categoryID: category.id,
                outflows: [
                    MoneyMovement(
                        accountID: account.id,
                        money: Money(currency: .usd, minorUnits: 1_300)
                    )
                ],
                inflows: []
            )
        ]
        let data = FinanceData(
            accounts: [account],
            categories: [category],
            transactions: transactions
        )
        let budget = LedgerBudget(
            categoryID: category.id,
            currency: .usd,
            monthlyLimit: Money(currency: .usd, minorUnits: 1_000),
            rollover: true,
            startedAt: january
        )

        XCTAssertEqual(financeBudgetAllowance(budget, in: data, interval: currentMonth).minorUnits, 1_200)
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

    func testMonthlySchedulePreservesDayAnchorAcrossShortMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let january31 = calendar.date(
            from: DateComponents(year: 2025, month: 1, day: 31, hour: 9)
        )!

        let february = ScheduleFrequency.monthly.nextDate(
            after: january31,
            calendar: calendar,
            monthlyDay: 31
        )!
        XCTAssertEqual(calendar.component(.day, from: february), 28)

        let march = ScheduleFrequency.monthly.nextDate(
            after: february,
            calendar: calendar,
            monthlyDay: 31
        )!
        XCTAssertEqual(calendar.component(.day, from: march), 31)

        let lastDayFebruary = ScheduleFrequency.monthly.nextDate(
            after: january31,
            calendar: calendar,
            monthlyRule: .lastDayOfMonth
        )!
        XCTAssertEqual(calendar.component(.day, from: lastDayFebruary), 28)
    }

    func testLegacyScheduledTransactionDecodesMonthlyDefaults() throws {
        let account = Account(
            name: "Cash",
            type: .cash,
            currency: .usd,
            openingBalance: Money(currency: .usd, minorUnits: 0)
        )
        let schedule = ScheduledTransaction(
            nextRunDate: Date(timeIntervalSince1970: 1_700_000_000),
            frequency: .monthly,
            note: "Rent",
            kind: .expense,
            categoryID: nil,
            outflows: [
                MoneyMovement(
                    accountID: account.id,
                    money: Money(currency: .usd, minorUnits: 1_000)
                )
            ],
            inflows: []
        )
        let encoded = try JSONEncoder().encode(schedule)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "monthlyRule")
        object.removeValue(forKey: "recurrenceDay")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ScheduledTransaction.self, from: legacyData)
        XCTAssertEqual(decoded.monthlyRule, .dayOfMonth)
        XCTAssertEqual(
            decoded.recurrenceDay,
            Calendar.current.component(.day, from: schedule.nextRunDate)
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

    func testWatchExpenseCommandRoundTripsThroughConnectivityCodec() throws {
        let command = WatchExpenseCommand(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            amount: Money(currency: .usd, minorUnits: 1_250),
            accountID: UUID(),
            categoryID: UUID(),
            note: "Coffee"
        )

        let context = try XCTUnwrap(WatchSyncCodec.dictionary(for: command))
        let decoded = try XCTUnwrap(WatchSyncCodec.expenseCommand(from: context))

        XCTAssertEqual(decoded, command)
    }

    func testWatchSnapshotIncludesBalancesAndRecentActivity() {
        let account = Account(
            name: "Cash",
            type: .cash,
            currency: .usd,
            openingBalance: Money(currency: .usd, minorUnits: 10_000)
        )
        let category = LedgerCategory(name: "Food")
        let transaction = LedgerTransaction(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            note: "Lunch",
            kind: .expense,
            categoryID: category.id,
            outflows: [
                MoneyMovement(
                    accountID: account.id,
                    money: Money(currency: .usd, minorUnits: 1_250)
                )
            ],
            inflows: []
        )

        let snapshot = WatchSyncPublisher.makeSnapshot(
            from: FinanceData(
                accounts: [account],
                categories: [category],
                transactions: [transaction]
            ),
            generatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        XCTAssertEqual(snapshot.balances.first { $0.currency == .usd }?.balance.minorUnits, 8_750)
        XCTAssertEqual(snapshot.accounts.first?.name, "Cash")
        XCTAssertEqual(snapshot.recentTransactions.first?.categoryPath, "Food")
        XCTAssertEqual(snapshot.recentTransactions.first?.amount.minorUnits, 1_250)
    }
}
