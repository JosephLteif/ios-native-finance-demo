import SwiftUI

struct WatchExpenseView: View {
    @ObservedObject var store: WatchLedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var note = ""
    @State private var accountID: UUID?
    @State private var categoryID: UUID?
    @State private var validationMessage: String?

    private var accounts: [WatchAccountSummary] {
        (store.snapshot?.accounts ?? []).filter(\.canUseForExpense)
    }

    private var categories: [WatchCategorySummary] {
        store.snapshot?.categories ?? []
    }

    private var selectedAccount: WatchAccountSummary? {
        accounts.first { $0.id == accountID }
    }

    private var parsedAmount: Money? {
        guard let currency = selectedAccount?.currency else { return nil }
        return Money.parse(amount, currency: currency)
    }

    var body: some View {
        Form {
            if accounts.isEmpty {
                Text("No active account is available for an expense.")
                    .foregroundStyle(.secondary)
            } else {
                TextField("Amount", text: $amount)

                Picker("Account", selection: $accountID) {
                    Text("Choose account").tag(nil as UUID?)
                    ForEach(accounts) { account in
                        Text("\(account.name) (\(account.currency.rawValue))")
                            .tag(Optional(account.id))
                    }
                }

                Picker("Category", selection: $categoryID) {
                    Text("Uncategorized").tag(nil as UUID?)
                    ForEach(categories) { category in
                        Text(category.path)
                            .tag(Optional(category.id))
                    }
                }

                TextField("Note", text: $note)

                Button("Queue expense") {
                    saveExpense()
                }
                .disabled((parsedAmount?.minorUnits ?? 0) <= 0 || accountID == nil)
            }
        }
        .navigationTitle("Expense")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .onAppear {
            if accountID == nil {
                accountID = accounts.first?.id
            }
        }
        .alert(
            "Cannot save expense",
            isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(validationMessage ?? "Check the expense details and try again.")
        }
    }

    private func saveExpense() {
        guard let accountID,
              let amount = parsedAmount,
              amount.minorUnits > 0 else {
            validationMessage = "Enter a positive amount and choose an account."
            return
        }

        store.queueExpense(
            amount: amount,
            accountID: accountID,
            categoryID: categoryID,
            note: note
        )
        dismiss()
    }
}
