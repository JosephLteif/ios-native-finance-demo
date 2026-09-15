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
        storage.isAppGroupAvailable
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
        data.transactions.append(transaction)
        saveData(successMessage: "Transaction saved")
    }

    func addAccount(_ account: Account) {
        data.accounts.append(account)
        saveData(successMessage: "Account added")
    }

    func addCategory(_ category: LedgerCategory) {
        data.categories.append(category)
        saveData(successMessage: "Category added")
    }

    func resetLedger() {
        data = .starter
        saveData(successMessage: "Ledger reset")
    }

    func reload() {
        guard storage.isAppGroupAvailable else { return }
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

    private func saveData(successMessage: String) {
        let persisted = storage.save(data)
        WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        lastActionStatus = persisted
            ? successMessage
            : "\(successMessage) for this session; shared storage is unavailable."
    }
}
