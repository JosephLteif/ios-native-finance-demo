import AppIntents

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
    }
}
