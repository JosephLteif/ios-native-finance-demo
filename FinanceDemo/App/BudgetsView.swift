import SwiftUI

@MainActor
struct BudgetsView: View {
    @ObservedObject var store: LedgerStore
    @State private var editingBudget: LedgerBudget?
    @State private var isPresentingEditor = false
    @State private var budgetToDelete: LedgerBudget?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Budgets")
                                .font(.largeTitle.weight(.bold))
                            Text("Keep monthly spending intentional")
                                .font(.subheadline)
                                .foregroundStyle(PocketLedgerTheme.textSecondary)
                        }
                        Spacer()
                        Button { presentNewBudget() } label: {
                                Image(systemName: "plus")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(PocketLedgerTheme.accent)
                                    .frame(minWidth: 44, minHeight: 44)
                                .pocketGlassSurface(
                                    cornerRadius: 22,
                                    tint: PocketLedgerTheme.accent.opacity(0.18),
                                    interactive: true
                                )
                        }
                        .accessibilityLabel("Add budget")
                        .accessibilityHint("Creates a new monthly budget")
                    }

                    if store.data.budgets.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "chart.bar.doc.horizontal")
                                .font(.title2)
                                .foregroundStyle(PocketLedgerTheme.textTertiary)
                            Text("No budgets yet").font(.headline)
                            Text("Set a monthly limit for a category to track progress here.")
                                .font(.subheadline)
                                .foregroundStyle(PocketLedgerTheme.textSecondary)
                                .multilineTextAlignment(.center)
                            Button("Create budget", action: presentNewBudget)
                                .buttonStyle(.glassProminent)
                                .tint(PocketLedgerTheme.accent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 42)
                        .padding(.horizontal, 20)
                        .pocketGlassSurface(cornerRadius: 20)
                    } else {
                        ForEach(store.data.budgets) { budget in
                            budgetCard(budget)
                        }
                    }
            }
            .padding(16)
        }
        .pocketScreen()
        .navigationTitle("Budgets")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingEditor, onDismiss: { editingBudget = nil }) {
            BudgetEditor(store: store, budget: editingBudget)
        }
        .confirmationDialog("Delete budget?", isPresented: Binding(
            get: { budgetToDelete != nil },
            set: { if !$0 { budgetToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let budgetToDelete { _ = store.deleteBudget(id: budgetToDelete.id) }
                self.budgetToDelete = nil
            }
            Button("Cancel", role: .cancel) { budgetToDelete = nil }
        }
    }

    private func budgetCard(_ budget: LedgerBudget) -> some View {
        let spent = store.budgetSpent(budget)
        let allowance = store.budgetAllowance(budget)
        let ratio = min(Double(spent.minorUnits) / Double(max(allowance.minorUnits, 1)), 1)
        let over = spent.minorUnits > allowance.minorUnits

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.categoryPath(for: budget.categoryID)).font(.headline)
                    Text("This month · \(budget.currency.rawValue)")
                        .font(.caption)
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                }
                Spacer()
                Text("\(spent.formatted) / \(allowance.formatted)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(over ? PocketLedgerTheme.warning : PocketLedgerTheme.textPrimary)
            }
            ProgressView(value: ratio)
                .tint(over ? PocketLedgerTheme.warning : PocketLedgerTheme.accent)
            HStack {
                Text(over ? "Over by \(Money(currency: budget.currency, minorUnits: spent.minorUnits - allowance.minorUnits).formatted)" : "Remaining \(Money(currency: budget.currency, minorUnits: allowance.minorUnits - spent.minorUnits).formatted)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(over ? PocketLedgerTheme.warning : PocketLedgerTheme.positive)
                Spacer()
                Button("Edit") { editingBudget = budget; isPresentingEditor = true }
                    .buttonStyle(.borderless)
                Button(role: .destructive) { budgetToDelete = budget } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Delete budget")
            }
        }
        .padding(16)
        .pocketGlassSurface(cornerRadius: 20)
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(PocketLedgerTheme.divider, lineWidth: 1) }
    }

    private func presentNewBudget() {
        editingBudget = nil
        isPresentingEditor = true
    }
}

@MainActor
private struct BudgetEditor: View {
    @ObservedObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let budget: LedgerBudget?
    @State private var categoryID: UUID?
    @State private var currency: LedgerCurrency
    @State private var amount: String
    @State private var rollover: Bool
    @State private var errorMessage: String?

    init(store: LedgerStore, budget: LedgerBudget?) {
        _store = ObservedObject(wrappedValue: store)
        self.budget = budget
        _categoryID = State(initialValue: budget?.categoryID ?? store.activeCategories.first?.id)
        _currency = State(initialValue: budget?.currency ?? .usd)
        _amount = State(initialValue: budget.map { NSDecimalNumber(decimal: Decimal($0.monthlyLimit.minorUnits) / Decimal($0.currency.minorUnitScale)).stringValue } ?? "")
        _rollover = State(initialValue: budget?.rollover ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Budget") {
                    Picker("Category", selection: $categoryID) {
                        ForEach(store.activeCategories) { category in
                            Text(store.categoryPath(for: category.id)).tag(Optional(category.id))
                        }
                    }
                    Picker("Currency", selection: $currency) {
                        ForEach(LedgerCurrency.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Monthly limit", text: $amount).keyboardType(.decimalPad)
                    Toggle("Rollover unused amount", isOn: $rollover)
                }
            }
            .navigationTitle(budget == nil ? "New budget" : "Edit budget")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
            .alert("Budget not saved", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var canSave: Bool {
        categoryID != nil && (Money.parse(amount, currency: currency)?.minorUnits ?? 0) > 0
    }

    private func save() {
        guard let categoryID, let limit = Money.parse(amount, currency: currency), limit.minorUnits > 0 else {
            errorMessage = "Enter a positive monthly limit."
            return
        }
        let saved = store.upsertBudget(
            LedgerBudget(
                id: budget?.id ?? UUID(),
                categoryID: categoryID,
                currency: currency,
                monthlyLimit: limit,
                rollover: rollover,
                startedAt: budget?.startedAt ?? .now
            )
        )
        if saved { dismiss() }
    }
}
