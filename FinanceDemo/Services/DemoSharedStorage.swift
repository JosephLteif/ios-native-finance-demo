import Foundation
import OSLog

final class DemoSharedStorage: @unchecked Sendable {
    static let appGroupIdentifier = "group.com.josephlteif.financedemo"

    private enum Key {
        static let balanceCents = "balance"
        static let lastTransactionDescription = "lastTransactionDescription"
        static let lastUpdated = "lastUpdated"
        static let lastWidgetRefresh = "lastWidgetRefresh"
    }

    private let context: String
    private let defaults: UserDefaults?
    private let containerURL: URL?
    private let logger = Logger(subsystem: "com.josephlteif.financedemo", category: "SharedStorage")

    // The widget has no safe fallback because its container cannot see the main app's
    // ordinary defaults. The main app and App Intents report the shared-storage
    // failure until the App Group entitlement is available.
    private var localBalanceCents = 100_000
    private var localLastTransactionDescription = "Starting Pocket Ledger balance"
    private var localLastUpdated = Date()
    private var localLastWidgetRefresh: Date?

    init(context: String) {
        self.context = context
        defaults = UserDefaults(suiteName: Self.appGroupIdentifier)
        containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        )

        if isAppGroupAvailable, let defaults {
            seedDefaultsIfNeeded(defaults)
        }

        logger.info(
            "context=\(context, privacy: .public) app_group=\(self.isAppGroupAvailable ? "WORKING" : "UNAVAILABLE", privacy: .public) storage=\(self.storageDefaults == nil ? "UNAVAILABLE" : "APP_GROUP", privacy: .public)"
        )
    }

    var isAppGroupAvailable: Bool {
        defaults != nil && containerURL != nil
    }

    var isAppStorageAvailable: Bool {
        storageDefaults != nil
    }

    func snapshot() -> DemoSnapshot {
        guard let defaults = storageDefaults else {
            logger.warning("context=\(self.context, privacy: .public) using in-memory diagnostic state")
            return DemoSnapshot(
                balanceCents: localBalanceCents,
                lastTransactionDescription: localLastTransactionDescription,
                lastUpdated: localLastUpdated,
                lastWidgetRefresh: localLastWidgetRefresh,
                appGroupAvailable: false,
                appStorageAvailable: false
            )
        }

        let lastWidgetRefreshValue = defaults.double(forKey: Key.lastWidgetRefresh)
        return DemoSnapshot(
            balanceCents: defaults.integer(forKey: Key.balanceCents),
            lastTransactionDescription: defaults.string(forKey: Key.lastTransactionDescription) ?? "Starting Pocket Ledger balance",
            lastUpdated: Date(timeIntervalSince1970: defaults.double(forKey: Key.lastUpdated)),
            lastWidgetRefresh: lastWidgetRefreshValue > 0 ? Date(timeIntervalSince1970: lastWidgetRefreshValue) : nil,
            appGroupAvailable: isAppGroupAvailable,
            appStorageAvailable: true
        )
    }

    @discardableResult
    func recordTransaction(deltaCents: Int, description: String) -> Bool {
        guard let defaults = storageDefaults else {
            logger.error("context=\(self.context, privacy: .public) transaction_not_saved=true")
            return false
        }

        let startingBalanceCents: Int
        if defaults.object(forKey: Key.balanceCents) != nil {
            startingBalanceCents = defaults.integer(forKey: Key.balanceCents)
        } else {
            startingBalanceCents = localBalanceCents
        }

        localBalanceCents = startingBalanceCents + deltaCents
        localLastTransactionDescription = description
        localLastUpdated = Date()

        defaults.set(localBalanceCents, forKey: Key.balanceCents)
        defaults.set(description, forKey: Key.lastTransactionDescription)
        defaults.set(localLastUpdated.timeIntervalSince1970, forKey: Key.lastUpdated)
        logger.info("context=\(self.context, privacy: .public) transaction_saved=true")
        return true
    }

    @discardableResult
    func resetDemoData() -> Bool {
        guard let defaults = storageDefaults else {
            logger.error("context=\(self.context, privacy: .public) reset_not_saved=true")
            return false
        }

        localBalanceCents = 100_000
        localLastTransactionDescription = "Reset Pocket Ledger balance"
        localLastUpdated = Date()
        localLastWidgetRefresh = nil

        defaults.set(localBalanceCents, forKey: Key.balanceCents)
        defaults.set(localLastTransactionDescription, forKey: Key.lastTransactionDescription)
        defaults.set(localLastUpdated.timeIntervalSince1970, forKey: Key.lastUpdated)
        defaults.removeObject(forKey: Key.lastWidgetRefresh)
        logger.info("context=\(self.context, privacy: .public) reset_saved=true")
        return true
    }

    @discardableResult
    func markWidgetReloadRequested() -> Bool {
        guard let defaults = storageDefaults else {
            logger.error("context=\(self.context, privacy: .public) widget_reload_saved=false")
            return false
        }

        let now = Date()
        localLastWidgetRefresh = now
        defaults.set(now.timeIntervalSince1970, forKey: Key.lastWidgetRefresh)
        logger.info("context=\(self.context, privacy: .public) widget_reload_saved=true")
        return true
    }

    private func seedDefaultsIfNeeded(_ defaults: UserDefaults) {
        if defaults.object(forKey: Key.balanceCents) == nil {
            defaults.set(100_000, forKey: Key.balanceCents)
        }
        if defaults.object(forKey: Key.lastTransactionDescription) == nil {
            defaults.set("Starting Pocket Ledger balance", forKey: Key.lastTransactionDescription)
        }
        if defaults.object(forKey: Key.lastUpdated) == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: Key.lastUpdated)
        }
    }

    private var storageDefaults: UserDefaults? {
        guard isAppGroupAvailable else { return nil }
        return defaults
    }
}
