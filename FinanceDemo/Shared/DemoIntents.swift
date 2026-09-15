import AppIntents
import WidgetKit

struct AddDemoExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Pocket Ledger Expense"
    static let description = IntentDescription("Subtracts $5 from the Pocket Ledger balance.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let storage = DemoSharedStorage(context: "app-intent")
        let saved = storage.recordTransaction(deltaCents: -500, description: "Interactive $5 expense")
        if saved {
            WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        }
        let balance = storage.snapshot().balanceText
        guard saved else {
            return .result(value: "Shared App Group unavailable", dialog: "The expense was not saved because the shared App Group is unavailable.")
        }
        return .result(value: balance, dialog: "Your Pocket Ledger balance is now \(balance).")
    }
}

struct AddDemoIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Pocket Ledger Income"
    static let description = IntentDescription("Adds $100 to the Pocket Ledger balance.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let storage = DemoSharedStorage(context: "app-intent")
        let saved = storage.recordTransaction(deltaCents: 10_000, description: "Interactive $100 income")
        if saved {
            WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        }
        let balance = storage.snapshot().balanceText
        guard saved else {
            return .result(value: "Shared App Group unavailable", dialog: "The income was not saved because the shared App Group is unavailable.")
        }
        return .result(value: balance, dialog: "Your Pocket Ledger balance is now \(balance).")
    }
}

struct ResetDemoDataIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset Pocket Ledger"
    static let description = IntentDescription("Resets the Pocket Ledger balance to $1,000.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let storage = DemoSharedStorage(context: "app-intent")
        let saved = storage.resetDemoData()
        if saved {
            WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        }
        let balance = storage.snapshot().balanceText
        guard saved else {
            return .result(value: "Shared App Group unavailable", dialog: "The demo was not reset because the shared App Group is unavailable.")
        }
        return .result(value: balance, dialog: "Pocket Ledger was reset. The balance is \(balance).")
    }
}

struct GetDemoBalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Pocket Ledger Balance"
    static let description = IntentDescription("Reads the current Pocket Ledger balance.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let snapshot = DemoSharedStorage(context: "app-intent").snapshot()
        guard snapshot.appGroupAvailable else {
            return .result(value: "Shared App Group unavailable", dialog: "The Pocket Ledger shared App Group is unavailable, so no shared balance can be read.")
        }
        return .result(value: snapshot.balanceText, dialog: "Your Pocket Ledger balance is \(snapshot.balanceText).")
    }
}
