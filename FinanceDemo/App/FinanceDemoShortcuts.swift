import AppIntents
import Foundation

struct GenerateBudgetSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Summarize Pocket Ledger Budget"
    static let description = IntentDescription("Uses Apple Intelligence to summarize the current Pocket Ledger balance and latest transaction.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let snapshot = FinanceStorage(context: "app-intent").widgetSnapshot()
        let summary = await FoundationModelService.generateBudgetSummary(for: snapshot)
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}

struct GetBudgetStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Pocket Ledger Budgets"
    static let description = IntentDescription("Returns this month's spending against each Pocket Ledger category budget.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let data = FinanceStorage(context: "app-intent").load()
        let month = Calendar.current.dateInterval(of: .month, for: .now)
        let lines = data.budgets.map { budget -> String in
            let spentMoney = financeBudgetSpent(budget, in: data, interval: month)
            let allowance = financeBudgetAllowance(budget, in: data, interval: month)
            let category = data.categories.first(where: { $0.id == budget.categoryID })?.name ?? "Uncategorized"
            let remaining = Money(currency: budget.currency, minorUnits: allowance.minorUnits - spentMoney.minorUnits)
            return "\(category): \(spentMoney.formatted) of \(allowance.formatted), \(remaining.minorUnits >= 0 ? "\(remaining.formatted) remaining" : "\(Money(currency: budget.currency, minorUnits: -remaining.minorUnits).formatted) over")"
        }
        let summary = lines.isEmpty ? "No budgets configured." : lines.joined(separator: "\n")
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}

struct FinanceDemoShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetDemoBalanceIntent(),
            phrases: [
                "Get my balance in \(.applicationName)",
                "What's my balance in \(.applicationName)",
                "Check my balance in \(.applicationName)"
            ],
            shortTitle: "Get Pocket Ledger Balance",
            systemImageName: "dollarsign.circle"
        )
        AppShortcut(
            intent: AddDemoExpenseIntent(),
            phrases: [
                "Add a five dollar expense in \(.applicationName)",
                "Spend five dollars in \(.applicationName)",
                "Add an expense in \(.applicationName)"
            ],
            shortTitle: "Add Pocket Ledger Expense",
            systemImageName: "minus.circle"
        )
        AppShortcut(
            intent: AddLedgerTransactionIntent(),
            phrases: [
                "Add a transaction to \(\.$account) in \(.applicationName)",
                "Record a transaction in \(.applicationName)"
            ],
            shortTitle: "Add Pocket Ledger Transaction",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: GetCategoriesIntent(),
            phrases: [
                "List my categories in \(.applicationName)",
                "Get my Pocket Ledger categories in \(.applicationName)"
            ],
            shortTitle: "Get Pocket Ledger Categories",
            systemImageName: "tag"
        )
        AppShortcut(
            intent: GetAccountsIntent(),
            phrases: [
                "List my accounts in \(.applicationName)",
                "Get my Pocket Ledger accounts in \(.applicationName)"
            ],
            shortTitle: "Get Pocket Ledger Accounts",
            systemImageName: "wallet.pass"
        )
        AppShortcut(
            intent: GetAccountBalanceIntent(),
            phrases: [
                "Get the balance of \(\.$account) in \(.applicationName)",
                "Check an account balance in \(.applicationName)"
            ],
            shortTitle: "Get Account Balance",
            systemImageName: "chart.bar.xaxis"
        )
        AppShortcut(
            intent: GetTransactionHistoryIntent(),
            phrases: [
                "Show my transactions for \(\.$period) in \(.applicationName)",
                "Show my \(\.$category) transactions in \(.applicationName)"
            ],
            shortTitle: "Get Transaction History",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: GetSpendingSummaryIntent(),
            phrases: [
                "How much did I spend \(\.$period) in \(.applicationName)",
                "How much did I spend on \(\.$category) in \(.applicationName)"
            ],
            shortTitle: "Get Spending Summary",
            systemImageName: "chart.bar.doc.horizontal"
        )
        AppShortcut(
            intent: GenerateBudgetSummaryIntent(),
            phrases: [
                "Summarize my Pocket Ledger budget in \(.applicationName)",
                "Give me a budget summary in \(.applicationName)"
            ],
            shortTitle: "Summarize Budget",
            systemImageName: "sparkles"
        ),
        AppShortcut(
            intent: GetBudgetStatusIntent(),
            phrases: [
                "Check my Pocket Ledger budgets in \(.applicationName)",
                "How are my budgets doing in \(.applicationName)"
            ],
            shortTitle: "Check Budgets",
            systemImageName: "chart.bar.doc.horizontal"
        )
    }
}
