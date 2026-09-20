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
    private let attachmentDirectory: URL?
    private let recoverySnapshotURL: URL?
    private(set) var loadStatus: LoadStatus = .notLoaded
    private(set) var saveConflict = false

    private struct RecoveryAttachment: Codable {
        let id: UUID
        let data: Data
    }

    private struct RecoverySnapshot: Codable {
        let data: FinanceData
        let attachments: [RecoveryAttachment]
    }

    init(context: String) {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ), let sharedContainer = Self.makeModelContainer(
            at: groupURL.appendingPathComponent("PocketLedger.sqlite")
        ) {
            modelContainer = sharedContainer
            storageLocation = .appGroup
            attachmentDirectory = Self.makeAttachmentDirectory(
                at: groupURL.appendingPathComponent("PocketLedgerAttachments", isDirectory: true)
            )
            recoverySnapshotURL = groupURL.appendingPathComponent("PocketLedger-last-good.json")
            return
        }

        guard context != "widget",
              let applicationSupportURL = FileManager.default.urls(
                  for: .applicationSupportDirectory,
                  in: .userDomainMask
              ).first else {
            modelContainer = nil
            storageLocation = .unavailable
            attachmentDirectory = nil
            recoverySnapshotURL = nil
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
            attachmentDirectory = nil
            recoverySnapshotURL = nil
            return
        }

        guard let localContainer = Self.makeModelContainer(
            at: localDirectory.appendingPathComponent("PocketLedger.sqlite")
        ) else {
            modelContainer = nil
            storageLocation = .unavailable
            attachmentDirectory = nil
            recoverySnapshotURL = nil
            return
        }

        modelContainer = localContainer
        storageLocation = .local
        attachmentDirectory = Self.makeAttachmentDirectory(
            at: localDirectory.appendingPathComponent("Attachments", isDirectory: true)
        )
        recoverySnapshotURL = localDirectory.appendingPathComponent("PocketLedger-last-good.json")
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

    var canStoreAttachments: Bool {
        attachmentDirectory != nil
    }

    @discardableResult
    func storeAttachment(_ data: Data, fileExtension: String) throws -> String {
        guard let attachmentDirectory else {
            throw CocoaError(.fileNoSuchFile)
        }

        let normalizedExtension = fileExtension
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let relativePath = UUID().uuidString + (normalizedExtension.isEmpty ? "" : ".\(normalizedExtension)")
        let url = attachmentDirectory.appendingPathComponent(relativePath, isDirectory: false)
        try data.write(to: url, options: .atomic)
        return relativePath
    }

    func attachmentData(relativePath: String) -> Data? {
        guard let url = attachmentURL(relativePath: relativePath) else { return nil }
        return try? Data(contentsOf: url)
    }

    func deleteAttachment(relativePath: String) {
        guard let url = attachmentURL(relativePath: relativePath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func deleteAllAttachments() {
        guard let attachmentDirectory else { return }
        try? FileManager.default.removeItem(at: attachmentDirectory)
        _ = Self.makeAttachmentDirectory(at: attachmentDirectory)
    }

    var hasRecoverySnapshot: Bool {
        guard let recoverySnapshotURL else { return false }
        return FileManager.default.fileExists(atPath: recoverySnapshotURL.path)
    }

    @discardableResult
    func writeRecoverySnapshot(_ value: FinanceData) -> Bool {
        guard let recoverySnapshotURL else { return false }

        var attachments: [RecoveryAttachment] = []
        for attachment in value.attachments {
            if let data = attachmentData(relativePath: attachment.relativePath) {
                attachments.append(RecoveryAttachment(id: attachment.id, data: data))
            }
        }

        let snapshot = RecoverySnapshot(data: value, attachments: attachments)
        guard let encoded = try? JSONEncoder().encode(snapshot) else { return false }

        do {
            try encoded.write(to: recoverySnapshotURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func loadRecoverySnapshot() -> (data: FinanceData, attachmentData: [UUID: Data])? {
        guard let recoverySnapshotURL,
              let encoded = try? Data(contentsOf: recoverySnapshotURL),
              let snapshot = try? JSONDecoder().decode(RecoverySnapshot.self, from: encoded) else {
            return nil
        }
        let attachmentData = snapshot.attachments.reduce(into: [UUID: Data]()) { result, attachment in
            result[attachment.id] = attachment.data
        }
        return (snapshot.data, attachmentData)
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
    func save(
        _ value: FinanceData,
        expected: FinanceData? = nil,
        allowingCorruptedReplacement: Bool = false
    ) -> Bool {
        saveConflict = false
        guard allowingCorruptedReplacement || !isCorrupted,
              let modelContainer,
              let encoded = try? JSONEncoder().encode(value) else {
            return false
        }

        let context = ModelContext(modelContainer)

        do {
            let records = try context.fetch(FetchDescriptor<FinanceDatabaseRecord>())
            if let record = records.first {
                if let expected {
                    if let current = try? JSONDecoder().decode(FinanceData.self, from: record.payload) {
                        if current != expected {
                            saveConflict = true
                            return false
                        }
                    } else if !allowingCorruptedReplacement {
                        loadStatus = .corrupted
                        return false
                    }
                }
                record.payload = encoded
            } else {
                if let expected, expected != .empty {
                    saveConflict = true
                    return false
                }
                context.insert(FinanceDatabaseRecord(payload: encoded))
            }

            try context.save()
            loadStatus = .loaded
            WatchSyncPublisher.publish(data: value)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func appendTransaction(_ transaction: LedgerTransaction) -> Bool {
        saveConflict = false
        guard let modelContainer, !isCorrupted else {
            return false
        }

        let context = ModelContext(modelContainer)
        do {
            let records = try context.fetch(FetchDescriptor<FinanceDatabaseRecord>())
            let value: FinanceData
            if let record = records.first {
                guard let decoded = try? JSONDecoder().decode(FinanceData.self, from: record.payload) else {
                    loadStatus = .corrupted
                    return false
                }
                value = decoded
            } else {
                value = .empty
            }

            guard FinanceTransactionValidator.validate(
                transaction,
                in: value,
                allowArchivedReferences: true
            ) == nil else {
                return false
            }

            var updated = value
            updated.transactions.append(transaction)
            let encoded = try JSONEncoder().encode(updated)
            if let record = records.first {
                record.payload = encoded
            } else {
                context.insert(FinanceDatabaseRecord(payload: encoded))
            }
            try context.save()
            loadStatus = .loaded
            WatchSyncPublisher.publish(data: updated)
            return true
        } catch {
            return false
        }
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
                .filter { !$0.isArchived && $0.currency == currency && $0.type != .loan && $0.includeInTotals }
                .reduce(Int64.zero) { $0 + balance(for: $1) }
            return Money(currency: currency, minorUnits: minorUnits)
        }

        let latest = value.transactions.max { $0.date < $1.date }
        let attentionCount = value.transactions.filter {
            $0.kind == .expense && $0.categoryID == nil
        }.count
            + value.budgets.filter { budget in
                let spent = financeBudgetSpent(budget, in: value)
                let allowance = financeBudgetAllowance(budget, in: value)
                return spent.minorUnits > allowance.minorUnits
            }.count
        let upcomingScheduledCount = value.scheduledTransactions.filter {
            $0.isEnabled
                && $0.nextRunDate <= (Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now)
        }.count

        return FinanceWidgetSnapshot(
            usdAvailable: availableBalance(for: .usd),
            lbpAvailable: availableBalance(for: .lbp),
            eurAvailable: availableBalance(for: .eur),
            latestTransactionDescription: latest?.note ?? "No transactions yet",
            lastUpdated: latest?.date ?? .now,
            appGroupAvailable: isAppGroupAvailable,
            attentionCount: attentionCount,
            upcomingScheduledCount: upcomingScheduledCount
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

    private static func makeAttachmentDirectory(at url: URL) -> URL? {
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
            return url
        } catch {
            return nil
        }
    }

    private func attachmentURL(relativePath: String) -> URL? {
        guard let attachmentDirectory,
              !relativePath.isEmpty,
              relativePath != ".",
              relativePath != "..",
              !relativePath.contains("/"),
              !relativePath.contains("\\") else {
            return nil
        }
        return attachmentDirectory.appendingPathComponent(relativePath, isDirectory: false)
    }
}
