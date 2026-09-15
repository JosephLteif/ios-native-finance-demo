import AppIntents
import WidgetKit

struct AddDemoExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Pocket Ledger Expense"
    static let description = IntentDescription("Adds a five dollar expense to the USD cash ledger.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let storage = FinanceStorage(context: "app-intent")
        let value = storage.load()
        guard let account = value.accounts.first(where: { $0.currency == .usd && $0.type != .loan }),
              let category = value.categories.first(where: { $0.parentID != nil }) else {
            return .result(
                value: "Ledger is not initialized",
                dialog: "Pocket Ledger could not find a USD account and expense category."
            )
        }

        let transaction = LedgerTransaction(
            note: "Interactive $5 expense",
            kind: .expense,
            categoryID: category.id,
            amountDue: Money(currency: .usd, minorUnits: 500),
            outflows: [
                MoneyMovement(
                    accountID: account.id,
                    money: Money(currency: .usd, minorUnits: 500)
                )
            ],
            inflows: []
        )
        let saved = storage.appendTransaction(transaction)
        guard saved else {
            return .result(
                value: "Shared App Group unavailable",
                dialog: "The expense was not saved because the shared App Group is unavailable."
            )
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        let balance = storage.widgetSnapshot().balanceSummary
        return .result(
            value: balance,
            dialog: "Your Pocket Ledger balances are now \(balance)."
        )
    }
}

struct AddDemoIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Pocket Ledger Income"
    static let description = IntentDescription("Adds one hundred dollars to the USD cash ledger.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let storage = FinanceStorage(context: "app-intent")
        let value = storage.load()
        guard let account = value.accounts.first(where: { $0.currency == .usd && $0.type != .loan }) else {
            return .result(
                value: "Ledger is not initialized",
                dialog: "Pocket Ledger could not find a USD account."
            )
        }

        let transaction = LedgerTransaction(
            note: "Interactive $100 income",
            kind: .income,
            categoryID: nil,
            outflows: [],
            inflows: [
                MoneyMovement(
                    accountID: account.id,
                    money: Money(currency: .usd, minorUnits: 10_000)
                )
            ]
        )
        let saved = storage.appendTransaction(transaction)
        guard saved else {
            return .result(
                value: "Shared App Group unavailable",
                dialog: "The income was not saved because the shared App Group is unavailable."
            )
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        let balance = storage.widgetSnapshot().balanceSummary
        return .result(
            value: balance,
            dialog: "Your Pocket Ledger balances are now \(balance)."
        )
    }
}

struct ResetDemoDataIntent: AppIntent {
    static let title: LocalizedStringResource = "Reset Pocket Ledger"
    static let description = IntentDescription("Clears the Pocket Ledger database and starts with no accounts, categories, or transactions.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let storage = FinanceStorage(context: "app-intent")
        let saved = storage.resetLedger()
        guard saved else {
            return .result(
                value: "Shared App Group unavailable",
                dialog: "The ledger was not reset because the shared App Group is unavailable."
            )
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        let balance = storage.widgetSnapshot().balanceSummary
        return .result(
            value: balance,
            dialog: "Pocket Ledger was cleared. The available balances are \(balance)."
        )
    }
}

struct GetDemoBalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Pocket Ledger Balance"
    static let description = IntentDescription("Reads the current USD and LBP balances.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let snapshot = FinanceStorage(context: "app-intent").widgetSnapshot()
        guard snapshot.appGroupAvailable else {
            return .result(
                value: "Shared App Group unavailable",
                dialog: "The Pocket Ledger shared App Group is unavailable, so no shared balances can be read."
            )
        }

        return .result(
            value: snapshot.balanceSummary,
            dialog: "Your Pocket Ledger balances are \(snapshot.balanceSummary)."
        )
    }
}
