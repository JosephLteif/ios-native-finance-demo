import AppIntents
import SwiftUI
import WidgetKit

struct AddExpenseControl: ControlWidget {
    static let kind = "com.josephlteif.financedemo.add-expense"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: AddDemoExpenseIntent()) {
                Label("Add expense", systemImage: "minus.circle.fill")
            }
        }
        .displayName("Add Pocket Ledger Expense")
        .description("Record a five dollar USD expense from Control Center or the Lock Screen.")
    }
}
