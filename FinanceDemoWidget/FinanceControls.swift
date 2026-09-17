import AppIntents
import SwiftUI
import WidgetKit

struct AddExpenseControl: ControlWidget {
    static let kind = "com.josephlteif.financedemo.add-expense"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            intent: QuickExpenseControlConfiguration.self
        ) { configuration in
            ControlWidgetButton(
                action: AddConfiguredExpenseIntent(amount: configuration.amount)
            ) {
                Label("Add \(configuration.amount)", systemImage: "minus.circle.fill")
            }
        }
        .displayName("Add Pocket Ledger Expense")
        .description("Record a configured USD expense from Control Center or the Lock Screen.")
        .promptsForUserConfiguration()
    }
}
