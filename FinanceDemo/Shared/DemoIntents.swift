import AppIntents
import WidgetKit

struct AddDemoExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Demo Expense"
    static let description = IntentDescription("Subtracts $5 from the shared Finance Native Demo balance.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        let storage = DemoSharedStorage(context: "app-intent")
        _ = storage.recordTransaction(deltaCents: -500, description: "Interactive $5 expense")
        WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        return .result()
    }
}

struct GetDemoBalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Demo Balance"
    static let description = IntentDescription("Reads the shared Finance Native Demo balance.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let snapshot = DemoSharedStorage(context: "app-intent").snapshot()
        return .result(value: snapshot.balanceText)
    }
}

struct FinanceDemoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetDemoBalanceIntent(),
            phrases: [
                "Get my demo balance in \(.applicationName)",
                "What's my finance demo balance in \(.applicationName)"
            ],
            shortTitle: "Get Demo Balance",
            systemImageName: "dollarsign.circle"
        )
    }
}
