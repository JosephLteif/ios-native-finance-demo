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

    // These values are deliberately process-local. They are never used as a silent
    // replacement for the App Group container when the entitlement is unavailable.
    private var localBalanceCents = 100_000
    private var localLastTransactionDescription = "Starting balance"
    private var localLastUpdated = Date()
    private var localLastWidgetRefresh: Date?

    init(context: String) {
        self.context = context
        defaults = UserDefaults(suiteName: Self.appGroupIdentifier)
        containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        )

        if isAppGroupAvailable {
            seedSharedDefaultsIfNeeded()
        }

        logger.info(
            "context=\(context, privacy: .public) app_group=\(self.isAppGroupAvailable ? "WORKING" : "UNAVAILABLE", privacy: .public)"
        )
    }

    var isAppGroupAvailable: Bool {
        defaults != nil && containerURL != nil
    }

    func snapshot() -> DemoSnapshot {
        guard isAppGroupAvailable, let defaults else {
            logger.warning("context=\(self.context, privacy: .public) using process-local diagnostic state")
            return DemoSnapshot(
                balanceCents: localBalanceCents,
                lastTransactionDescription: localLastTransactionDescription,
                lastUpdated: localLastUpdated,
                lastWidgetRefresh: localLastWidgetRefresh,
                appGroupAvailable: false
            )
        }

        let lastWidgetRefreshValue = defaults.double(forKey: Key.lastWidgetRefresh)
        return DemoSnapshot(
            balanceCents: defaults.integer(forKey: Key.balanceCents),
            lastTransactionDescription: defaults.string(forKey: Key.lastTransactionDescription) ?? "Starting balance",
            lastUpdated: Date(timeIntervalSince1970: defaults.double(forKey: Key.lastUpdated)),
            lastWidgetRefresh: lastWidgetRefreshValue > 0 ? Date(timeIntervalSince1970: lastWidgetRefreshValue) : nil,
            appGroupAvailable: true
        )
    }

    @discardableResult
    func recordTransaction(deltaCents: Int, description: String) -> Bool {
        localBalanceCents += deltaCents
        localLastTransactionDescription = description
        localLastUpdated = Date()

        guard isAppGroupAvailable, let defaults else {
            logger.error("context=\(self.context, privacy: .public) transaction_not_shared=true")
            return false
        }

        defaults.set(localBalanceCents, forKey: Key.balanceCents)
        defaults.set(description, forKey: Key.lastTransactionDescription)
        defaults.set(localLastUpdated.timeIntervalSince1970, forKey: Key.lastUpdated)
        logger.info("context=\(self.context, privacy: .public) transaction_shared=true")
        return true
    }

    @discardableResult
    func markWidgetReloadRequested() -> Bool {
        let now = Date()
        localLastWidgetRefresh = now

        guard isAppGroupAvailable, let defaults else {
            logger.error("context=\(self.context, privacy: .public) widget_reload_shared=false")
            return false
        }

        defaults.set(now.timeIntervalSince1970, forKey: Key.lastWidgetRefresh)
        logger.info("context=\(self.context, privacy: .public) widget_reload_shared=true")
        return true
    }

    private func seedSharedDefaultsIfNeeded() {
        guard let defaults else { return }

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
}

