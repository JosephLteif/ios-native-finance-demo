import AppIntents
import WidgetKit

struct AddDemoExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Demo Expense"
    static let description = IntentDescription("Subtracts $5 from the shared Finance Native Demo balance.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let storage = DemoSharedStorage(context: "app-intent")
        _ = storage.recordTransaction(deltaCents: -500, description: "Interactive $5 expense")
        WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        return .result(value: storage.snapshot().balanceText)
    }
}

struct AddDemoIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Demo Income"
    static let description = IntentDescription("Adds $100 to the shared Finance Native Demo balance.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let storage = DemoSharedStorage(context: "app-intent")
        _ = storage.recordTransaction(deltaCents: 10_000, description: "Interactive $100 income")
        WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        return .result(value: storage.snapshot().balanceText)
    }
}

struct ResetDemoDataIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset Finance Demo"
    static let description = IntentDescription("Resets the Finance Native Demo balance to $1,000.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let storage = DemoSharedStorage(context: "app-intent")
        _ = storage.resetDemoData()
        WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        return .result(value: storage.snapshot().balanceText)
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
