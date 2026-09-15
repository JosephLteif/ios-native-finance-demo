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
            transaction.date >= monthStart
        }.count
    }

    var topCategoryThisMonth: String? {
        var counts: [UUID: Int] = [:]
        for transaction in data.transactions where transaction.kind == .expense && transaction.date >= monthStart {
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

    func addAccount(_ account: Account) {
        var updated = data
        updated.accounts.append(account)
        persist(updated, successMessage: "Account added")
    }

    func addCategory(_ category: LedgerCategory) {
        var updated = data
        updated.categories.append(category)
        persist(updated, successMessage: "Category added")
    }

    func resetLedger() {
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

        updated.accounts.append(contentsOf: imported.accounts.filter { !accountIDs.contains($0.id) })
        updated.categories.append(contentsOf: imported.categories.filter { !categoryIDs.contains($0.id) })
        updated.transactions.append(contentsOf: imported.transactions.filter { !transactionIDs.contains($0.id) })

        return persist(updated, successMessage: "Import completed")
    }

    func reload() {
        data = storage.load()
    }

    func account(with id: UUID) -> Account? {
        data.accounts.first { $0.id == id }
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
            .filter { $0.currency == currency && $0.type != .loan }
            .reduce(Int64.zero) { $0 + balance(for: $1).minorUnits }
        return Money(currency: currency, minorUnits: totalMinorUnits)
    }

    func loanBalance(for currency: LedgerCurrency) -> Money {
        let totalMinorUnits = data.accounts
            .filter { $0.currency == currency && $0.type == .loan }
            .reduce(Int64.zero) { $0 + balance(for: $1).minorUnits }
        return Money(currency: currency, minorUnits: totalMinorUnits)
    }

    func monthlyExpenseTotals() -> [LedgerCurrency: Int64] {
        var totals: [LedgerCurrency: Int64] = [:]

        for transaction in data.transactions where transaction.kind == .expense && transaction.date >= monthStart {
            for movement in transaction.outflows {
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
        lastActionStatus = successMessage
        return true
    }
}
