import Foundation
import SwiftData

final class FinanceStorage {
    static let appGroupIdentifier = "group.com.josephlteif.financedemo"

    private enum StorageLocation: Equatable {
        case appGroup
        case local
        case unavailable
    }

    enum LoadStatus {
        case notLoaded
        case empty
        case loaded
        case corrupted
    }

    private let modelContainer: ModelContainer?
    private let storageLocation: StorageLocation
    private(set) var loadStatus: LoadStatus = .notLoaded

    init(context: String) {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ), let sharedContainer = Self.makeModelContainer(
            at: groupURL.appendingPathComponent("PocketLedger.sqlite")
        ) {
            modelContainer = sharedContainer
            storageLocation = .appGroup
            return
        }

        guard context != "widget",
              let applicationSupportURL = FileManager.default.urls(
                  for: .applicationSupportDirectory,
                  in: .userDomainMask
              ).first else {
            modelContainer = nil
            storageLocation = .unavailable
            return
        }

        let localDirectory = applicationSupportURL.appendingPathComponent("PocketLedger", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: localDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            modelContainer = nil
            storageLocation = .unavailable
            return
        }

        guard let localContainer = Self.makeModelContainer(
            at: localDirectory.appendingPathComponent("PocketLedger.sqlite")
        ) else {
            modelContainer = nil
            storageLocation = .unavailable
            return
        }

        modelContainer = localContainer
        storageLocation = .local
    }

    var isPersistent: Bool {
        modelContainer != nil
    }

    var isAppGroupAvailable: Bool {
        storageLocation == .appGroup
    }

    var isLocalFallback: Bool {
        storageLocation == .local
    }

    var isCorrupted: Bool {
        loadStatus == .corrupted
    }

    func load() -> FinanceData {
        guard let context = makeContext() else {
            loadStatus = .empty
            return .empty
        }

        guard let records = try? context.fetch(FetchDescriptor<FinanceDatabaseRecord>()) else {
            loadStatus = .corrupted
            return .empty
        }

        guard let record = records.first else {
            loadStatus = .empty
            return .empty
        }

        guard let decoded = try? JSONDecoder().decode(FinanceData.self, from: record.payload) else {
            loadStatus = .corrupted
            return .empty
        }

        loadStatus = .loaded
        return decoded
    }

    @discardableResult
    func save(_ value: FinanceData, allowingCorruptedReplacement: Bool = false) -> Bool {
        guard allowingCorruptedReplacement || !isCorrupted,
              let modelContainer,
              let encoded = try? JSONEncoder().encode(value) else {
            return false
        }

        let context = ModelContext(modelContainer)

        do {
            let records = try context.fetch(FetchDescriptor<FinanceDatabaseRecord>())
            if let record = records.first {
                record.payload = encoded
            } else {
                context.insert(FinanceDatabaseRecord(payload: encoded))
            }

            try context.save()
            loadStatus = .loaded
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func appendTransaction(_ transaction: LedgerTransaction) -> Bool {
        var value = load()
        value.transactions.append(transaction)
        return save(value)
    }

    @discardableResult
    func resetLedger() -> Bool {
        save(.empty)
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

        func availableBalance(for currency: LedgerCurrency) -> Money {
            let minorUnits = value.accounts
                .filter { $0.currency == currency && $0.type != .loan && $0.includeInTotals }
                .reduce(Int64.zero) { $0 + balance(for: $1) }
            return Money(currency: currency, minorUnits: minorUnits)
        }

        let latest = value.transactions.max { $0.date < $1.date }

        return FinanceWidgetSnapshot(
            usdAvailable: availableBalance(for: .usd),
            lbpAvailable: availableBalance(for: .lbp),
            eurAvailable: availableBalance(for: .eur),
            latestTransactionDescription: latest?.note ?? "No transactions yet",
            lastUpdated: latest?.date ?? .now,
            appGroupAvailable: isAppGroupAvailable
        )
    }

    private func makeContext() -> ModelContext? {
        guard let modelContainer else { return nil }
        return ModelContext(modelContainer)
    }

    private static func makeModelContainer(at databaseURL: URL) -> ModelContainer? {
        let schema = Schema([FinanceDatabaseRecord.self])
        let configuration = ModelConfiguration(
            schema: schema,
            url: databaseURL,
            cloudKitDatabase: .none
        )
        return try? ModelContainer(for: schema, configurations: [configuration])
    }
}
