import Combine
import Foundation
import UIKit
import WidgetKit

@MainActor
final class DemoStore: ObservableObject {
    @Published private(set) var snapshot: DemoSnapshot
    @Published private(set) var foundationModelStatus: String
    @Published private(set) var foundationModelResult: String?
    @Published private(set) var foundationModelInput: String?
    @Published private(set) var notificationStatus: String?
    @Published private(set) var lastActionStatus: String?
    @Published private(set) var isWorking = false

    private let storage = DemoSharedStorage(context: "main-app")

    init() {
        snapshot = storage.snapshot()
        foundationModelStatus = FoundationModelService.availabilityDescription()
        foundationModelInput = nil
    }

    var iosVersion: String {
        UIDevice.current.systemVersion
    }

    func addExpense() {
        let saved = storage.recordTransaction(deltaCents: -500, description: "Added $5 expense")
        requestWidgetReload()
        refreshSnapshot()
        foundationModelResult = nil
        foundationModelInput = nil
        lastActionStatus = saved ? savedStorageMessage("Expense saved") : "Expense could not be saved."
    }

    func addIncome() {
        let saved = storage.recordTransaction(deltaCents: 10_000, description: "Added $100 income")
        requestWidgetReload()
        refreshSnapshot()
        foundationModelResult = nil
        foundationModelInput = nil
        lastActionStatus = saved ? savedStorageMessage("Income saved") : "Income could not be saved."
    }

    func resetDemo() {
        let saved = storage.resetDemoData()
        requestWidgetReload()
        refreshSnapshot()
        foundationModelResult = nil
        foundationModelInput = nil
        lastActionStatus = saved ? savedStorageMessage("Pocket Ledger reset to $1,000") : "Pocket Ledger data could not be saved."
    }

    func refreshWidget() {
        let saved = requestWidgetReload()
        refreshSnapshot()
        lastActionStatus = saved ? "Widget reload requested." : "Widget reload requested, but no app storage is available."
    }

    func testNotification() async {
        guard !isWorking else { return }
        isWorking = true
        notificationStatus = await NotificationService.scheduleDemoNotification()
        isWorking = false
    }

    func testAppleIntelligence() async {
        guard !isWorking else { return }
        isWorking = true
        let inputSnapshot = storage.snapshot()
        foundationModelStatus = FoundationModelService.availabilityDescription()
        foundationModelInput = inputSnapshot.balanceText
        foundationModelResult = await FoundationModelService.generateBudgetSummary(for: inputSnapshot)
        foundationModelStatus = FoundationModelService.availabilityDescription()
        isWorking = false
    }

    private func refreshSnapshot() {
        snapshot = storage.snapshot()
    }

    private func savedStorageMessage(_ action: String) -> String {
        if storage.isAppGroupAvailable {
            return "\(action) in the shared App Group."
        }
        return "\(action) in local app storage. Widgets still need App Group signing."
    }

    @discardableResult
    private func requestWidgetReload() -> Bool {
        let shared = storage.isAppGroupAvailable && storage.markWidgetReloadRequested()
        WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        return shared
    }
}
