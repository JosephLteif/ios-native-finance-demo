import SwiftUI

struct WatchExpenseView: View {
    @ObservedObject var store: WatchLedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var note = ""
    @State private var accountID: UUID?
    @State private var categoryID: UUID?
    @State private var validationMessage: String?
    @State private var saveFeedbackTrigger = 0

    private var accounts: [WatchAccountSummary] {
        (store.snapshot?.accounts ?? []).filter(\.canUseForExpense)
    }

    private var categories: [WatchCategorySummary] {
        store.snapshot?.categories ?? []
    }

    private var categorySections: [CategorySection] {
        var groupedCategories: [String: [WatchCategorySummary]] = [:]
        for category in categories {
            let parentName = category.path.split(separator: "/", maxSplits: 1).first.map(String.init)
                ?? category.path
            groupedCategories[parentName, default: []].append(category)
        }

        var sections: [CategorySection] = []
        for (parentName, categories) in groupedCategories {
            let sortedCategories = categories.sorted { lhs, rhs in
                lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
            }
            sections.append(CategorySection(
                parentName: parentName,
                categories: sortedCategories
            ))
        }

        return sections.sorted { lhs, rhs in
            lhs.parentName.localizedCaseInsensitiveCompare(rhs.parentName) == .orderedAscending
        }
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
                    ForEach(categorySections) { section in
                        Section {
                            ForEach(section.categories) { category in
                                Text(categoryLabel(category, parentName: section.parentName))
                                    .tag(Optional(category.id))
                            }
                        } header: {
                            Text(section.parentName)
                        }
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
        .sensoryFeedback(.success, trigger: saveFeedbackTrigger)
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

    private func categoryLabel(_ category: WatchCategorySummary, parentName: String) -> String {
        guard category.path != parentName else { return category.path }
        let childName = category.path.split(separator: "/").dropFirst().joined(separator: " / ")
        return "  \(childName)"
    }

    private struct CategorySection: Identifiable {
        let parentName: String
        let categories: [WatchCategorySummary]

        var id: String { parentName }
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
        saveFeedbackTrigger += 1
        dismiss()
    }
}
