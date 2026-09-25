import SwiftUI

@MainActor
struct BudgetsView: View {
    @ObservedObject var store: LedgerStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingBudget: LedgerBudget?
    @State private var isPresentingEditor = false
    @State private var budgetToDelete: LedgerBudget?
    @State private var budgetSummaries: [DashboardBudgetSnapshot] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                    Text("Keep monthly spending intentional")
                        .font(.subheadline)
                        .foregroundStyle(PocketLedgerTheme.textSecondary)

                    if budgetSummaries.isEmpty {
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
                        .pocketGroupedSurface(cornerRadius: 20)
                    } else {
                        ForEach(budgetSummaries) { summary in
                            budgetCard(summary)
                        }
                    }
            }
            .padding(16)
        }
        .pocketScreen()
        .navigationTitle("Budgets")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: presentNewBudget) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add budget")
                .accessibilityHint("Creates a new monthly budget")
            }
        }
        .sheet(isPresented: $isPresentingEditor, onDismiss: { editingBudget = nil }) {
            BudgetEditor(store: store, budget: editingBudget)
        }
        .onAppear(perform: refreshBudgetSummaries)
        .onChange(of: store.ledgerRevision) { _, _ in
            withAnimation(PocketLedgerMotion.expressive(reduceMotion: reduceMotion)) {
                refreshBudgetSummaries()
            }
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

    private func budgetCard(_ summary: DashboardBudgetSnapshot) -> some View {
        let budget = summary.budget
        let spent = summary.spent
        let allowance = summary.allowance
        let ratio = summary.ratio
        let over = summary.isOver
        let remaining = summary.remaining
        let projectedOver = summary.isProjectedOver

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.categoryPath).font(.headline)
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
                .tint(projectedOver ? PocketLedgerTheme.warning : PocketLedgerTheme.accent)
                .animation(PocketLedgerMotion.expressive(reduceMotion: reduceMotion), value: ratio)
            Text(over
                 ? "Over by \(Money(currency: budget.currency, minorUnits: -remaining).formatted)"
                 : "Remaining \(Money(currency: budget.currency, minorUnits: remaining).formatted)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(over ? PocketLedgerTheme.warning : PocketLedgerTheme.positive)
            HStack {
                Text("Projected \(summary.projected.formatted)")
                    .font(.caption)
                    .foregroundStyle(projectedOver ? PocketLedgerTheme.warning : PocketLedgerTheme.textSecondary)
                Spacer()
                Text("\(summary.daysLeft) days left")
                    .font(.caption)
                    .foregroundStyle(PocketLedgerTheme.textTertiary)
            }
            HStack {
                NavigationLink {
                    TransactionsView(
                        store: store,
                        initialFilter: .expense,
                        initialPeriod: .thisMonth,
                        initialSearch: summary.categoryPath
                    )
                } label: {
                    Label("View transactions", systemImage: "list.bullet")
                }
                .buttonStyle(.glass)
                .tint(PocketLedgerTheme.accent)
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
        .pocketGroupedSurface(cornerRadius: 20)
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(PocketLedgerTheme.divider, lineWidth: 1) }
    }

    private func presentNewBudget() {
        editingBudget = nil
        isPresentingEditor = true
    }

    private func refreshBudgetSummaries() {
        budgetSummaries = DashboardSnapshot.makeBudgetSummaries(
            data: store.data,
            index: store.ledgerIndex
        )
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
                        CategoryPickerContent(
                            categories: store.activeCategories,
                            includeUncategorized: false
                        )
                    }
                    CurrencyInputField("Monthly limit", text: $amount, currency: $currency)
                    Toggle("Rollover unused amount", isOn: $rollover)
                }
            }
            .pocketListSurface()
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
