import Foundation

enum WatchLedgerConstants {
    static let appGroupIdentifier = "group.com.josephlteif.financedemo"
    static let cacheKey = "watchLedgerCache"
    static let snapshotKey = "snapshot"
    static let expenseCommandKey = "expenseCommand"
    static let acknowledgementKey = "acknowledgement"
}

struct WatchBalanceSummary: Identifiable, Codable, Equatable, Sendable {
    let currency: LedgerCurrency
    let balance: Money

    var id: String { currency.rawValue }
}

struct WatchAccountSummary: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let currency: LedgerCurrency
    let balance: Money
    let canUseForExpense: Bool
}

struct WatchCategorySummary: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let path: String
}

struct WatchTransactionSummary: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let note: String
    let kind: String
    let amount: Money
    let accountName: String
    let categoryPath: String?
}

struct WatchLedgerSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let generatedAt: Date
    let balances: [WatchBalanceSummary]
    let accounts: [WatchAccountSummary]
    let categories: [WatchCategorySummary]
    let recentTransactions: [WatchTransactionSummary]
}

struct WatchExpenseCommand: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let id: UUID
    let date: Date
    let amount: Money
    let accountID: UUID
    let categoryID: UUID?
    let note: String

    init(
        id: UUID = UUID(),
        date: Date = .now,
        amount: Money,
        accountID: UUID,
        categoryID: UUID?,
        note: String
    ) {
        version = Self.currentVersion
        self.id = id
        self.date = date
        self.amount = amount
        self.accountID = accountID
        self.categoryID = categoryID
        self.note = note
    }
}

struct WatchExpenseAcknowledgement: Codable, Equatable, Sendable {
    let commandID: UUID
    let accepted: Bool
    let message: String
}

struct WatchLedgerCache: Codable, Equatable {
    var snapshot: WatchLedgerSnapshot?
    var pendingExpenses: [WatchExpenseCommand]
    var lastSyncDate: Date?
    var lastError: String?

    static let empty = WatchLedgerCache(
        snapshot: nil,
        pendingExpenses: [],
        lastSyncDate: nil,
        lastError: nil
    )
}

enum WatchSyncCodec {
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func dictionary(for snapshot: WatchLedgerSnapshot) -> [String: Any]? {
        guard let data = try? makeEncoder().encode(snapshot) else { return nil }
        return [WatchLedgerConstants.snapshotKey: data]
    }

    static func dictionary(for command: WatchExpenseCommand) -> [String: Any]? {
        guard let data = try? makeEncoder().encode(command) else { return nil }
        return [WatchLedgerConstants.expenseCommandKey: data]
    }

    static func dictionary(for acknowledgement: WatchExpenseAcknowledgement) -> [String: Any]? {
        guard let data = try? makeEncoder().encode(acknowledgement) else { return nil }
        return [WatchLedgerConstants.acknowledgementKey: data]
    }

    static func snapshot(from context: [String: Any]) -> WatchLedgerSnapshot? {
        decode(WatchLedgerSnapshot.self, from: context[WatchLedgerConstants.snapshotKey])
    }

    static func expenseCommand(from context: [String: Any]) -> WatchExpenseCommand? {
        decode(WatchExpenseCommand.self, from: context[WatchLedgerConstants.expenseCommandKey])
    }

    static func acknowledgement(from context: [String: Any]) -> WatchExpenseAcknowledgement? {
        decode(WatchExpenseAcknowledgement.self, from: context[WatchLedgerConstants.acknowledgementKey])
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from value: Any?) -> Value? {
        guard let data = value as? Data else { return nil }
        return try? makeDecoder().decode(type, from: data)
    }
}

final class WatchLedgerCacheStore {
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: WatchLedgerConstants.appGroupIdentifier) ?? .standard
    }

    func load() -> WatchLedgerCache {
        guard let data = defaults.data(forKey: WatchLedgerConstants.cacheKey),
              let cache = try? JSONDecoder().decode(WatchLedgerCache.self, from: data) else {
            return .empty
        }
        return cache
    }

    func save(_ cache: WatchLedgerCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: WatchLedgerConstants.cacheKey)
    }
}
