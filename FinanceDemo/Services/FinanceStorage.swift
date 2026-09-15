import Foundation

final class FinanceStorage {
    static let appGroupIdentifier = "group.com.josephlteif.financedemo"
    private static let dataKey = "financeData"

    private let defaults: UserDefaults?
    private let containerURL: URL?
    private var inMemoryData = FinanceData.starter

    init(context: String) {
        defaults = UserDefaults(suiteName: Self.appGroupIdentifier)
        containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        )
    }

    var isAppGroupAvailable: Bool {
        defaults != nil && containerURL != nil
    }

    func load() -> FinanceData {
        guard let defaults,
              let data = defaults.data(forKey: Self.dataKey),
              let decoded = try? JSONDecoder().decode(FinanceData.self, from: data) else {
            inMemoryData = .starter
            return inMemoryData
        }

        inMemoryData = decoded
        return decoded
    }

    @discardableResult
    func save(_ value: FinanceData) -> Bool {
        inMemoryData = value

        guard isAppGroupAvailable,
              let defaults,
              let encoded = try? JSONEncoder().encode(value) else {
            return false
        }

        defaults.set(encoded, forKey: Self.dataKey)
        return true
    }

    @discardableResult
    func appendTransaction(_ transaction: LedgerTransaction) -> Bool {
        var value = load()
        value.transactions.append(transaction)
        return save(value)
    }

    @discardableResult
    func resetLedger() -> Bool {
        return save(.starter)
    }

    func widgetSnapshot() -> FinanceWidgetSnapshot {
        let value = load()

        func balance(for account: Account) -> Int64 {
            var balance = account.openingBalance.minorUnits

            for transaction in value.transactions {
                for movement in transaction.outflows where movement.accountID == account.id {
                    guard movement.money.currency == account.currency else { continue }
                    balance -= movement.money.minorUnits
                }
                for movement in transaction.inflows where movement.accountID == account.id {
                    guard movement.money.currency == account.currency else { continue }
                    balance += movement.money.minorUnits
                }
            }

            return balance
        }

        let usdBalance = value.accounts
            .filter { $0.currency == .usd && $0.type != .loan }
            .reduce(Int64.zero) { $0 + balance(for: $1) }
        let lbpBalance = value.accounts
            .filter { $0.currency == .lbp && $0.type != .loan }
            .reduce(Int64.zero) { $0 + balance(for: $1) }
        let latest = value.transactions.max { $0.date < $1.date }

        return FinanceWidgetSnapshot(
            usdAvailable: Money(currency: .usd, minorUnits: usdBalance),
            lbpAvailable: Money(currency: .lbp, minorUnits: lbpBalance),
            latestTransactionDescription: latest?.note ?? "No transactions yet",
            lastUpdated: latest?.date ?? .now,
            appGroupAvailable: isAppGroupAvailable
        )
    }
}
