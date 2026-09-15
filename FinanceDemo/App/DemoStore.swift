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
        let shared = storage.recordTransaction(deltaCents: -500, description: "Added $5 expense")
        requestWidgetReload()
        refreshSnapshot()
        foundationModelResult = nil
        foundationModelInput = nil
        lastActionStatus = shared ? "Expense saved to the shared App Group." : "Expense kept only as diagnostic process-local state."
    }

    func addIncome() {
        let shared = storage.recordTransaction(deltaCents: 10_000, description: "Added $100 income")
        requestWidgetReload()
        refreshSnapshot()
        foundationModelResult = nil
        foundationModelInput = nil
        lastActionStatus = shared ? "Income saved to the shared App Group." : "Income kept only as diagnostic process-local state."
    }

    func resetDemo() {
        let shared = storage.resetDemoData()
        requestWidgetReload()
        refreshSnapshot()
        foundationModelResult = nil
        foundationModelInput = nil
        lastActionStatus = shared ? "Demo data reset to $1,000 in the shared App Group." : "Demo data reset only in diagnostic process-local state."
    }

    func refreshWidget() {
        let shared = requestWidgetReload()
        refreshSnapshot()
        lastActionStatus = shared ? "Widget reload requested and timestamp shared." : "Widget reload requested, but the App Group is unavailable."
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

    @discardableResult
    private func requestWidgetReload() -> Bool {
        let shared = storage.markWidgetReloadRequested()
        WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        return shared
    }
}
