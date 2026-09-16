import Combine
import Foundation
import WidgetKit

@MainActor
final class LedgerStore: ObservableObject {
    @Published private(set) var data: FinanceData
    @Published private(set) var lastActionStatus: String?

    private let storage = FinanceStorage(context: "main-app")

    init() {
        data = storage.load()
    }

    var storageAvailable: Bool {
        storage.isPersistent
    }

    var sharedStorageAvailable: Bool {
        storage.isAppGroupAvailable
    }

    var storageStatus: String {
        if storage.isAppGroupAvailable {
            return "Persistent database is working"
        }
        if storage.isLocalFallback {
            return "Persistent local database is working; widget sharing is unavailable"
        }
        return "Persistent database unavailable"
    }

    var recentTransactions: [LedgerTransaction] {
        data.transactions.sorted { $0.date > $1.date }
    }

    var rootCategories: [LedgerCategory] {
        data.categories.filter { $0.parentID == nil }
    }

    var monthTransactionCount: Int {
        data.transactions.filter { transaction in
            transaction.date >= monthStart && transactionHasIncludedAccount(transaction)
        }.count
    }

    var topCategoryThisMonth: String? {
        var counts: [UUID: Int] = [:]
        for transaction in data.transactions where transaction.kind == .expense
            && transaction.date >= monthStart
            && transaction.outflows.contains(where: { includesInTotals(accountID: $0.accountID) }) {
            guard let categoryID = transaction.categoryID else { continue }
            counts[categoryID, default: 0] += 1
        }

        guard let categoryID = counts.max(by: { $0.value < $1.value })?.key else {
            return nil
        }
        return categoryPath(for: categoryID)
    }

    func addTransaction(_ transaction: LedgerTransaction) {
        var updated = data
        updated.transactions.append(transaction)
        persist(updated, successMessage: "Transaction saved")
    }

    @discardableResult
    func addScheduledTransaction(_ scheduledTransaction: ScheduledTransaction) -> Bool {
        var updated = data
        updated.scheduledTransactions.append(scheduledTransaction)

        guard persist(updated, successMessage: "Transaction scheduled") else { return false }
        if scheduledTransaction.isEnabled,
           scheduledTransaction.nextRunDate <= .now {
            processDueScheduledTransactions()
        }
        return true
    }

    @discardableResult
    func updateScheduledTransaction(_ scheduledTransaction: ScheduledTransaction) -> Bool {
        guard let index = data.scheduledTransactions.firstIndex(where: { $0.id == scheduledTransaction.id }) else {
            lastActionStatus = "Scheduled transaction not found"
            return false
        }

        var updated = data
        updated.scheduledTransactions[index] = scheduledTransaction
        guard persist(updated, successMessage: "Scheduled transaction updated") else { return false }

        if scheduledTransaction.isEnabled,
           scheduledTransaction.nextRunDate <= .now {
            processDueScheduledTransactions()
        }
        return true
    }

    @discardableResult
    func setScheduledTransactionEnabled(id: UUID, isEnabled: Bool) -> Bool {
        guard let index = data.scheduledTransactions.firstIndex(where: { $0.id == id }) else {
            lastActionStatus = "Scheduled transaction not found"
            return false
        }

        var scheduledTransaction = data.scheduledTransactions[index]
        guard !(isEnabled && scheduledTransaction.frequency == .once && scheduledTransaction.lastRunDate != nil) else {
            lastActionStatus = "Completed one-time transactions cannot be re-enabled"
            return false
        }
        scheduledTransaction.isEnabled = isEnabled
        var updated = data
        updated.scheduledTransactions[index] = scheduledTransaction
        let persisted = persist(
            updated,
            successMessage: isEnabled ? "Scheduled transaction enabled" : "Scheduled transaction paused"
        )
        if persisted, isEnabled, scheduledTransaction.nextRunDate <= .now {
            processDueScheduledTransactions()
        }
        return persisted
    }

    @discardableResult
    func deleteScheduledTransaction(id: UUID) -> Bool {
        var updated = data
        let originalCount = updated.scheduledTransactions.count
        updated.scheduledTransactions.removeAll { $0.id == id }
        guard updated.scheduledTransactions.count != originalCount else {
            lastActionStatus = "Scheduled transaction not found"
            return false
        }
        return persist(updated, successMessage: "Scheduled transaction deleted")
    }

    @discardableResult
    func processDueScheduledTransactions(now: Date = .now) -> Int {
        var updated = data
        var materializedCount = 0
        var changed = false
        let calendar = Calendar.current

        for index in updated.scheduledTransactions.indices {
            var scheduledTransaction = updated.scheduledTransactions[index]
            guard scheduledTransaction.isEnabled else { continue }

            var dueDate = scheduledTransaction.nextRunDate
            while scheduledTransaction.isEnabled && dueDate <= now {
                updated.transactions.append(scheduledTransaction.materializedTransaction(on: dueDate))
                materializedCount += 1
                changed = true
                scheduledTransaction.lastRunDate = dueDate

                guard scheduledTransaction.frequency != .once else {
                    scheduledTransaction.isEnabled = false
                    break
                }

                guard let nextDate = scheduledTransaction.frequency.nextDate(after: dueDate, calendar: calendar),
                      nextDate > dueDate else {
                    scheduledTransaction.isEnabled = false
                    break
                }

                scheduledTransaction.nextRunDate = nextDate
                dueDate = nextDate
            }

            updated.scheduledTransactions[index] = scheduledTransaction
        }

        guard changed else { return 0 }
        guard persist(
            updated,
            successMessage: "Added \(materializedCount) scheduled transaction\(materializedCount == 1 ? "" : "s")"
        ) else { return 0 }
        return materializedCount
    }

    func addAccount(_ account: Account) {
        var updated = data
        updated.accounts.append(account)
        persist(updated, successMessage: "Account added")
    }

    @discardableResult
    func setAccountIncludedInTotals(accountID: UUID, included: Bool) -> Bool {
        guard let accountIndex = data.accounts.firstIndex(where: { $0.id == accountID }) else {
            lastActionStatus = "Account not found"
            return false
        }

        var updated = data
        updated.accounts[accountIndex].includeInTotals = included
        return persist(
            updated,
            successMessage: included ? "Account included in totals" : "Account excluded from totals"
        )
    }

    func addCategory(_ category: LedgerCategory) {
        var updated = data
        updated.categories.append(category)
        persist(updated, successMessage: "Category added")
    }

    func exchangeRate(base: LedgerCurrency, quote: LedgerCurrency) -> ExchangeRate? {
        guard base != quote else { return nil }

        if let exact = data.exchangeRates.first(where: {
            $0.baseCurrency == base && $0.quoteCurrency == quote
        }) {
            return exact
        }

        guard let reverse = data.exchangeRates.first(where: {
            $0.baseCurrency == quote && $0.quoteCurrency == base
        }), reverse.quoteUnitsPerBaseUnit > 0 else {
            return nil
        }

        return ExchangeRate(
            baseCurrency: base,
            quoteCurrency: quote,
            quoteUnitsPerBaseUnit: Decimal(1) / reverse.quoteUnitsPerBaseUnit
        )
    }

    @discardableResult
    func upsertExchangeRate(_ exchangeRate: ExchangeRate) -> Bool {
        guard exchangeRate.baseCurrency != exchangeRate.quoteCurrency,
              exchangeRate.quoteUnitsPerBaseUnit > 0 else {
            lastActionStatus = "Enter a positive rate between two different currencies"
            return false
        }

        var updated = data
        updated.exchangeRates.removeAll {
            Set([
                $0.baseCurrency,
                $0.quoteCurrency
            ]) == Set([
                exchangeRate.baseCurrency,
                exchangeRate.quoteCurrency
            ])
        }
        updated.exchangeRates.append(exchangeRate)
        return persist(updated, successMessage: "Exchange rate saved")
    }

    @discardableResult
    func deleteExchangeRate(_ exchangeRate: ExchangeRate) -> Bool {
        var updated = data
        let originalCount = updated.exchangeRates.count
        updated.exchangeRates.removeAll { $0.id == exchangeRate.id }
        guard updated.exchangeRates.count != originalCount else {
            lastActionStatus = "Exchange rate not found"
            return false
        }
        return persist(updated, successMessage: "Exchange rate deleted")
    }

    @discardableResult
    func resetLedger() -> Bool {
        persist(.empty, successMessage: "Ledger reset")
    }

    @discardableResult
    func replaceData(_ imported: FinanceData) -> Bool {
        persist(imported, successMessage: "Ledger restored")
    }

    @discardableResult
    func mergeData(_ imported: FinanceData) -> Bool {
        var updated = data
        let accountIDs = Set(updated.accounts.map(\.id))
        let categoryIDs = Set(updated.categories.map(\.id))
        let transactionIDs = Set(updated.transactions.map(\.id))
        let scheduledTransactionIDs = Set(updated.scheduledTransactions.map(\.id))

        updated.accounts.append(contentsOf: imported.accounts.filter { !accountIDs.contains($0.id) })
        updated.categories.append(contentsOf: imported.categories.filter { !categoryIDs.contains($0.id) })
        updated.transactions.append(contentsOf: imported.transactions.filter { !transactionIDs.contains($0.id) })
        updated.scheduledTransactions.append(
            contentsOf: imported.scheduledTransactions.filter { !scheduledTransactionIDs.contains($0.id) }
        )
        for rate in imported.exchangeRates {
            updated.exchangeRates.removeAll {
                Set([$0.baseCurrency, $0.quoteCurrency]) == Set([rate.baseCurrency, rate.quoteCurrency])
            }
            updated.exchangeRates.append(rate)
        }

        return persist(updated, successMessage: "Import completed")
    }

    func reload() {
        data = storage.load()
    }

    func account(with id: UUID) -> Account? {
        data.accounts.first { $0.id == id }
    }

    func includesInTotals(accountID: UUID) -> Bool {
        account(with: accountID)?.includeInTotals ?? true
    }

    func transactionHasIncludedAccount(_ transaction: LedgerTransaction) -> Bool {
        (transaction.outflows + transaction.inflows).contains {
            includesInTotals(accountID: $0.accountID)
        }
    }

    func balance(for account: Account) -> Money {
        var balance = account.openingBalance.minorUnits

        for transaction in data.transactions {
            for movement in transaction.outflows where movement.accountID == account.id {
                guard movement.money.currency == account.currency else { continue }
                balance -= movement.money.minorUnits
            }
            for movement in transaction.inflows where movement.accountID == account.id {
                guard movement.money.currency == account.currency else { continue }
                balance += movement.money.minorUnits
            }
        }

        return Money(currency: account.currency, minorUnits: balance)
    }

    @discardableResult
    func updateAccountBalance(
        accountID: UUID,
        targetBalance: Money,
        recordAsTransaction: Bool,
        note: String
    ) -> Bool {
        guard let account = account(with: accountID),
              account.currency == targetBalance.currency else {
            lastActionStatus = "Balance update failed: currency mismatch."
            return false
        }

        let currentBalance = balance(for: account)
        let difference = targetBalance.minorUnits - currentBalance.minorUnits

        guard difference != 0 else {
            lastActionStatus = "Balance already matches"
            return true
        }

        var updated = data
        if recordAsTransaction {
            let adjustmentMoney = Money(
                currency: account.currency,
                minorUnits: Swift.abs(difference)
            )
            let adjustment = LedgerTransaction(
                date: .now,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Balance adjustment"
                    : note.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: difference > 0 ? .income : .expense,
                categoryID: nil,
                outflows: difference < 0
                    ? [MoneyMovement(accountID: account.id, money: adjustmentMoney)]
                    : [],
                inflows: difference > 0
                    ? [MoneyMovement(accountID: account.id, money: adjustmentMoney)]
                    : []
            )
            updated.transactions.append(adjustment)
        } else if let accountIndex = updated.accounts.firstIndex(where: { $0.id == accountID }) {
            updated.accounts[accountIndex].openingBalance = Money(
                currency: account.currency,
                minorUnits: account.openingBalance.minorUnits + difference
            )
        }

        return persist(
            updated,
            successMessage: recordAsTransaction
                ? "Balance adjustment saved as a transaction"
                : "Balance updated without a transaction"
        )
    }

    func availableBalance(for currency: LedgerCurrency) -> Money {
        let totalMinorUnits = data.accounts
            .filter { $0.currency == currency && $0.type != .loan && $0.includeInTotals }
            .reduce(Int64.zero) { $0 + balance(for: $1).minorUnits }
        return Money(currency: currency, minorUnits: totalMinorUnits)
    }

    func loanBalance(for currency: LedgerCurrency) -> Money {
        let totalMinorUnits = data.accounts
            .filter { $0.currency == currency && $0.type == .loan && $0.includeInTotals }
            .reduce(Int64.zero) { $0 + balance(for: $1).minorUnits }
        return Money(currency: currency, minorUnits: totalMinorUnits)
    }

    func monthlyExpenseTotals() -> [LedgerCurrency: Int64] {
        var totals: [LedgerCurrency: Int64] = [:]

        for transaction in data.transactions where transaction.kind == .expense && transaction.date >= monthStart {
            for movement in transaction.outflows where includesInTotals(accountID: movement.accountID) {
                totals[movement.money.currency, default: 0] += movement.money.minorUnits
            }
        }

        return totals
    }

    func categoryPath(for categoryID: UUID?) -> String {
        guard let categoryID else { return "Uncategorized" }

        var names: [String] = []
        var currentID: UUID? = categoryID
        var visited: Set<UUID> = []

        while let id = currentID,
              !visited.contains(id),
              let category = data.categories.first(where: { $0.id == id }) {
            visited.insert(id)
            names.insert(category.name, at: 0)
            currentID = category.parentID
        }

        return names.isEmpty ? "Uncategorized" : names.joined(separator: " / ")
    }

    func transactionSummary(_ transaction: LedgerTransaction) -> String {
        let outflowText = transaction.outflows.map { $0.money.formatted }.joined(separator: " + ")
        let inflowText = transaction.inflows.map { $0.money.formatted }.joined(separator: " + ")

        if outflowText.isEmpty { return "+ \(inflowText)" }
        if inflowText.isEmpty { return "− \(outflowText)" }
        return "\(outflowText)  →  \(inflowText)"
    }

    private var monthStart: Date {
        Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .distantPast
    }

    @discardableResult
    private func persist(_ updated: FinanceData, successMessage: String) -> Bool {
        let persisted = storage.save(updated)
        guard persisted else {
            lastActionStatus = "\(successMessage) was not saved because the persistent database is unavailable."
            return false
        }

        data = updated
        WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        FinanceDemoShortcuts.updateAppShortcutParameters()
        Task {
            await FinanceIntentIndexing.shared.refresh()
        }
        lastActionStatus = successMessage
        return true
    }
}
