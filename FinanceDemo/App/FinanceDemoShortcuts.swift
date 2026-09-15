import AppIntents

struct GenerateBudgetSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Summarize Demo Budget"
    static let description = IntentDescription("Uses Apple Intelligence to summarize the current Finance Demo balance and latest transaction.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let snapshot = DemoSharedStorage(context: "app-intent").snapshot()
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
                "Get my demo balance in \(.applicationName)",
                "What's my finance demo balance in \(.applicationName)",
                "Check my balance in \(.applicationName)"
            ],
            shortTitle: "Get Demo Balance",
            systemImageName: "dollarsign.circle"
        )
        AppShortcut(
            intent: AddDemoExpenseIntent(),
            phrases: [
                "Add a five dollar expense in \(.applicationName)",
                "Spend five dollars in \(.applicationName)",
                "Add an expense in \(.applicationName)"
            ],
            shortTitle: "Add Expense",
            systemImageName: "minus.circle"
        )
        AppShortcut(
            intent: AddDemoIncomeIntent(),
            phrases: [
                "Add a hundred dollars of income in \(.applicationName)",
                "Deposit one hundred dollars in \(.applicationName)",
                "Add income in \(.applicationName)"
            ],
            shortTitle: "Add Income",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: ResetDemoDataIntent(),
            phrases: [
                "Reset my finance demo in \(.applicationName)",
                "Reset the demo balance in \(.applicationName)",
                "Reset \(.applicationName)"
            ],
            shortTitle: "Reset Demo",
            systemImageName: "arrow.counterclockwise.circle"
        )
        AppShortcut(
            intent: GenerateBudgetSummaryIntent(),
            phrases: [
                "Summarize my demo budget in \(.applicationName)",
                "Give me a finance summary in \(.applicationName)",
                "Summarize \(.applicationName)"
            ],
            shortTitle: "Summarize Budget",
            systemImageName: "apple.intelligence"
        )
    }
}
