import Foundation
import SwiftUI
import WatchConnectivity
import WidgetKit

enum WatchSyncStatus: Equatable {
    case unavailable
    case connecting
    case synced
    case queued
    case error

    var title: String {
        switch self {
        case .unavailable:
            return "Watch sync unavailable"
        case .connecting:
            return "Connecting to iPhone"
        case .synced:
            return "Synced"
        case .queued:
            return "Waiting to sync"
        case .error:
            return "Sync needs attention"
        }
    }

    var systemImage: String {
        switch self {
        case .unavailable:
            return "iphone.slash"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark.circle.fill"
        case .queued:
            return "clock"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
final class WatchLedgerStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot: WatchLedgerSnapshot?
    @Published private(set) var pendingExpenses: [WatchExpenseCommand]
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var status: WatchSyncStatus
    @Published private(set) var errorMessage: String?

    private let cacheStore: WatchLedgerCacheStore
    private let session: WCSession

    override init() {
        cacheStore = WatchLedgerCacheStore()
        session = WCSession.default

        let cache = cacheStore.load()
        snapshot = cache.snapshot
        pendingExpenses = cache.pendingExpenses
        lastSyncedAt = cache.lastSyncDate
        status = WCSession.isSupported() && cacheStore.usesSharedContainer
            ? (cache.pendingExpenses.isEmpty ? .connecting : .queued)
            : .unavailable
        errorMessage = cache.lastError
        super.init()
    }

    func activate() {
        guard WCSession.isSupported(), cacheStore.usesSharedContainer else {
            status = .unavailable
            return
        }

        session.delegate = self
        status = .connecting
        session.activate()
    }

    func queueExpense(
        amount: Money,
        accountID: UUID,
        categoryID: UUID?,
        note: String
    ) {
        let command = WatchExpenseCommand(
            amount: amount,
            accountID: accountID,
            categoryID: categoryID,
            note: note
        )
        pendingExpenses.append(command)
        errorMessage = nil
        status = .queued
        saveCache()
        sendPendingExpenses()
    }

    private func sendPendingExpenses() {
        guard session.activationState == .activated else { return }

        for expense in pendingExpenses {
            guard let context = WatchSyncCodec.dictionary(for: expense) else { continue }
            session.transferUserInfo(context)
        }
    }

    private func handleActivation(isActivated: Bool, errorMessage: String?) {
        if let errorMessage {
            status = .error
            self.errorMessage = errorMessage
            saveCache()
            return
        }

        guard isActivated else {
            status = .connecting
            return
        }

        self.errorMessage = nil
        status = pendingExpenses.isEmpty ? .synced : .queued
        sendPendingExpenses()
        saveCache()
    }

    private func apply(_ snapshot: WatchLedgerSnapshot) {
        self.snapshot = snapshot
        lastSyncedAt = Date()
        errorMessage = nil

        let receivedTransactionIDs = Set(snapshot.recentTransactions.map(\.id))
        pendingExpenses.removeAll { receivedTransactionIDs.contains($0.id) }
        status = pendingExpenses.isEmpty ? .synced : .queued
        saveCache()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func handle(_ acknowledgement: WatchExpenseAcknowledgement) {
        guard pendingExpenses.contains(where: { $0.id == acknowledgement.commandID }) else {
            return
        }

        if acknowledgement.accepted {
            pendingExpenses.removeAll { $0.id == acknowledgement.commandID }
            errorMessage = nil
            status = pendingExpenses.isEmpty ? .synced : .queued
        } else {
            status = .error
            errorMessage = acknowledgement.message
        }
        saveCache()
    }

    private func saveCache() {
        cacheStore.save(
            WatchLedgerCache(
                snapshot: snapshot,
                pendingExpenses: pendingExpenses,
                lastSyncDate: lastSyncedAt,
                lastError: errorMessage
            )
        )
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let isActivated = activationState == .activated
        let message = error?.localizedDescription
        Task { @MainActor [weak self] in
            self?.handleActivation(isActivated: isActivated, errorMessage: message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let snapshot = WatchSyncCodec.snapshot(from: applicationContext) else { return }
        Task { @MainActor [weak self] in
            self?.apply(snapshot)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let snapshot = WatchSyncCodec.snapshot(from: userInfo) {
            Task { @MainActor [weak self] in
                self?.apply(snapshot)
            }
        }
        if let acknowledgement = WatchSyncCodec.acknowledgement(from: userInfo) {
            Task { @MainActor [weak self] in
                self?.handle(acknowledgement)
            }
        }
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.activate()
        }
    }
#endif
}
