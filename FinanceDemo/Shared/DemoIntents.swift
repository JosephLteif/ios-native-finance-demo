import AppIntents
import WidgetKit

struct AddDemoExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Demo Expense"
    static let description = IntentDescription("Subtracts $5 from the Finance Demo balance.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let storage = DemoSharedStorage(context: "app-intent")
        _ = storage.recordTransaction(deltaCents: -500, description: "Interactive $5 expense")
        WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        let balance = storage.snapshot().balanceText
        return .result(value: balance, dialog: "Your Finance Demo balance is now \(balance).")
    }
}

struct AddDemoIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Demo Income"
    static let description = IntentDescription("Adds $100 to the Finance Demo balance.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let storage = DemoSharedStorage(context: "app-intent")
        _ = storage.recordTransaction(deltaCents: 10_000, description: "Interactive $100 income")
        WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        let balance = storage.snapshot().balanceText
        return .result(value: balance, dialog: "Your Finance Demo balance is now \(balance).")
    }
}

struct ResetDemoDataIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset Finance Demo"
    static let description = IntentDescription("Resets the Finance Demo balance to $1,000.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let storage = DemoSharedStorage(context: "app-intent")
        _ = storage.resetDemoData()
        WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        let balance = storage.snapshot().balanceText
        return .result(value: balance, dialog: "Finance Demo was reset. The balance is \(balance).")
    }
}

struct GetDemoBalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Demo Balance"
    static let description = IntentDescription("Reads the current Finance Demo balance.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let snapshot = DemoSharedStorage(context: "app-intent").snapshot()
        return .result(value: snapshot.balanceText, dialog: "Your Finance Demo balance is \(snapshot.balanceText).")
    }
}
