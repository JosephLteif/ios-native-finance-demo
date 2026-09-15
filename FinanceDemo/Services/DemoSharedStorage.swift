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
    private let fallbackDefaults: UserDefaults?
    private let containerURL: URL?
    private let logger = Logger(subsystem: "com.josephlteif.financedemo", category: "SharedStorage")

    // The widget has no safe fallback because its container cannot see the main app's
    // ordinary defaults. The main app and App Intents can use the app's own defaults
    // until the App Group entitlement is available.
    private var localBalanceCents = 100_000
    private var localLastTransactionDescription = "Starting balance"
    private var localLastUpdated = Date()
    private var localLastWidgetRefresh: Date?

    init(context: String) {
        self.context = context
        defaults = UserDefaults(suiteName: Self.appGroupIdentifier)
        fallbackDefaults = context == "widget" ? nil : UserDefaults.standard
        containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        )

        if let storageDefaults {
            seedDefaultsIfNeeded(storageDefaults)
        }

        logger.info(
            "context=\(context, privacy: .public) app_group=\(self.isAppGroupAvailable ? "WORKING" : "UNAVAILABLE", privacy: .public) storage=\(self.storageDefaults == nil ? "UNAVAILABLE" : (self.isAppGroupAvailable ? "APP_GROUP" : "LOCAL_APP"), privacy: .public)"
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
            lastTransactionDescription: defaults.string(forKey: Key.lastTransactionDescription) ?? "Starting balance",
            lastUpdated: Date(timeIntervalSince1970: defaults.double(forKey: Key.lastUpdated)),
            lastWidgetRefresh: lastWidgetRefreshValue > 0 ? Date(timeIntervalSince1970: lastWidgetRefreshValue) : nil,
            appGroupAvailable: isAppGroupAvailable,
            appStorageAvailable: true
        )
    }

    @discardableResult
    func recordTransaction(deltaCents: Int, description: String) -> Bool {
        let startingBalanceCents: Int
        if let defaults = storageDefaults, defaults.object(forKey: Key.balanceCents) != nil {
            startingBalanceCents = defaults.integer(forKey: Key.balanceCents)
        } else {
            startingBalanceCents = localBalanceCents
        }

        localBalanceCents = startingBalanceCents + deltaCents
        localLastTransactionDescription = description
        localLastUpdated = Date()

        guard let defaults = storageDefaults else {
            logger.error("context=\(self.context, privacy: .public) transaction_not_saved=true")
            return false
        }

        defaults.set(localBalanceCents, forKey: Key.balanceCents)
        defaults.set(description, forKey: Key.lastTransactionDescription)
        defaults.set(localLastUpdated.timeIntervalSince1970, forKey: Key.lastUpdated)
        logger.info("context=\(self.context, privacy: .public) transaction_saved=true")
        return true
    }

    @discardableResult
    func resetDemoData() -> Bool {
        localBalanceCents = 100_000
        localLastTransactionDescription = "Reset demo balance"
        localLastUpdated = Date()
        localLastWidgetRefresh = nil

        guard let defaults = storageDefaults else {
            logger.error("context=\(self.context, privacy: .public) reset_not_saved=true")
            return false
        }

        defaults.set(localBalanceCents, forKey: Key.balanceCents)
        defaults.set(localLastTransactionDescription, forKey: Key.lastTransactionDescription)
        defaults.set(localLastUpdated.timeIntervalSince1970, forKey: Key.lastUpdated)
        defaults.removeObject(forKey: Key.lastWidgetRefresh)
        logger.info("context=\(self.context, privacy: .public) reset_saved=true")
        return true
    }

    @discardableResult
    func markWidgetReloadRequested() -> Bool {
        let now = Date()
        localLastWidgetRefresh = now

        guard let defaults = storageDefaults else {
            logger.error("context=\(self.context, privacy: .public) widget_reload_saved=false")
            return false
        }

        defaults.set(now.timeIntervalSince1970, forKey: Key.lastWidgetRefresh)
        logger.info("context=\(self.context, privacy: .public) widget_reload_saved=true")
        return true
    }

    private func seedDefaultsIfNeeded(_ defaults: UserDefaults) {
        if defaults.object(forKey: Key.balanceCents) == nil {
            defaults.set(100_000, forKey: Key.balanceCents)
        }
        if defaults.object(forKey: Key.lastTransactionDescription) == nil {
            defaults.set("Starting balance", forKey: Key.lastTransactionDescription)
        }
        if defaults.object(forKey: Key.lastUpdated) == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: Key.lastUpdated)
        }
    }

    private var storageDefaults: UserDefaults? {
        if isAppGroupAvailable {
            return defaults
        }
        return fallbackDefaults
    }
}
