import Foundation
import SwiftUI

@MainActor
struct AccountDetailView: View {
    @ObservedObject var store: LedgerStore
    let accountID: UUID

    @State private var isPresentingAccountEditor = false
    @State private var isPresentingBalanceEditor = false

    private var account: Account? {
        store.account(with: accountID)
    }

    var body: some View {
        content
            .navigationTitle(account?.name ?? "Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if account != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isPresentingAccountEditor = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel("Edit account")
                    }
                }
            }
            .sheet(isPresented: $isPresentingAccountEditor) {
                if let account {
                    AccountEditor(store: store, account: account)
                }
            }
            .sheet(isPresented: $isPresentingBalanceEditor) {
                if let account {
                    AccountBalanceEditor(store: store, account: account)
                }
            }
            .pocketScreen()
    }

    @ViewBuilder
    private var content: some View {
        if let account {
            accountContent(account)
        } else {
            ContentUnavailableView("Account unavailable", systemImage: "wallet.pass")
        }
    }

    private func accountContent(_ account: Account) -> some View {
        let transactions = store.recentTransactions.filter { transaction in
            transaction.outflows.contains { $0.accountID == account.id }
                || transaction.inflows.contains { $0.accountID == account.id }
        }
        let outgoing = transactions.reduce(Int64.zero) { total, transaction in
            total + transaction.outflows
                .filter { $0.accountID == account.id && $0.money.currency == account.currency }
                .reduce(Int64.zero) { $0 + $1.money.minorUnits }
        }
        let incoming = transactions.reduce(Int64.zero) { total, transaction in
            total + transaction.inflows
                .filter { $0.accountID == account.id && $0.money.currency == account.currency }
                .reduce(Int64.zero) { $0 + $1.money.minorUnits }
        }

        return ScrollView(showsIndicators: false) {
            PocketGlassContainer(spacing: 14) {
                VStack(alignment: .leading, spacing: 18) {
                    balanceCard(account)
                    totalsScopeCard(account)

                    HStack(spacing: 10) {
                        accountMetric(
                            title: "Transactions",
                            value: "\(transactions.count)",
                            systemImage: "arrow.left.arrow.right",
                            tint: PocketLedgerTheme.accent
                        )
                        accountMetric(
                            title: "Money in",
                            value: Money(currency: account.currency, minorUnits: incoming).formatted,
                            systemImage: "arrow.down.left",
                            tint: PocketLedgerTheme.income
                        )
                        accountMetric(
                            title: "Money out",
                            value: Money(currency: account.currency, minorUnits: outgoing).formatted,
                            systemImage: "arrow.up.right",
                            tint: PocketLedgerTheme.warning
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Account activity")
                                .font(.title3.weight(.bold))
                            Spacer()
                            Text("All time")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(PocketLedgerTheme.textTertiary)
                        }

                        if transactions.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .font(.title2)
                                    .foregroundStyle(PocketLedgerTheme.textTertiary)
                                Text("No transactions for this account")
                                    .font(.headline)
                                Text("Transactions that use this account will appear here.")
                                    .font(.subheadline)
                                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(transactions) { transaction in
                                    AccountTransactionRow(
                                        transaction: transaction,
                                        account: account,
                                        store: store
                                    )
                                    Divider().overlay(PocketLedgerTheme.divider)
                                }
                            }
                            .padding(.horizontal, 14)
                            .pocketGlassSurface(cornerRadius: 18)
                            .overlay {
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(PocketLedgerTheme.divider, lineWidth: 1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private func totalsScopeCard(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Include in totals and metrics", isOn: Binding(
                get: { account.includeInTotals },
                set: { store.setAccountIncludedInTotals(accountID: account.id, included: $0) }
            ))
            Text(account.includeInTotals
                 ? "This account contributes to balances and spending metrics."
                 : "This account stays visible here but is excluded from balances and spending metrics.")
                .font(.footnote)
                .foregroundStyle(PocketLedgerTheme.textSecondary)
        }
        .tint(PocketLedgerTheme.accent)
        .padding(16)
        .pocketGlassSurface(cornerRadius: 18)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(PocketLedgerTheme.divider, lineWidth: 1)
        }
    }

    private func balanceCard(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(account.type.displayName, systemImage: account.type.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                Spacer()
                Text(account.currency.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PocketLedgerTheme.accent)
            }

            Text(store.balance(for: account).formatted)
                .font(.largeTitle.weight(.bold).monospacedDigit())
                .monospacedDigit()
                .lineLimit(2)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                Text("Reconcile this balance")
            }
            .font(.caption)
            .foregroundStyle(PocketLedgerTheme.textTertiary)

            Button {
                isPresentingBalanceEditor = true
            } label: {
                Label("Adjust current balance", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(PocketLedgerTheme.accent)
        }
        .padding(20)
        .pocketGlassSurface(cornerRadius: 22, tint: PocketLedgerTheme.accent.opacity(0.08))
    }

    private func accountMetric(title: String, value: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(2)
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.4)
                .foregroundStyle(PocketLedgerTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(11)
        .pocketGlassSurface(cornerRadius: 16)
    }
}

@MainActor
private struct AccountTransactionRow: View {
    let transaction: LedgerTransaction
    let account: Account
    @ObservedObject var store: LedgerStore

    private var outgoing: Int64 {
        transaction.outflows
            .filter { $0.accountID == account.id && $0.money.currency == account.currency }
            .reduce(Int64.zero) { $0 + $1.money.minorUnits }
    }

    private var incoming: Int64 {
        transaction.inflows
            .filter { $0.accountID == account.id && $0.money.currency == account.currency }
            .reduce(Int64.zero) { $0 + $1.money.minorUnits }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .pocketGlassSurface(cornerRadius: 18, tint: tint.opacity(0.12))

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.note)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                    .lineLimit(1)
                Text(transaction.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.caption2)
                    .foregroundStyle(PocketLedgerTheme.textTertiary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                if outgoing > 0 {
                    Text("− " + Money(currency: account.currency, minorUnits: outgoing).formatted)
                        .foregroundStyle(PocketLedgerTheme.warning)
                }
                if incoming > 0 {
                    Text("+ " + Money(currency: account.currency, minorUnits: incoming).formatted)
                        .foregroundStyle(PocketLedgerTheme.income)
                }
            }
            .font(.caption.weight(.semibold).monospacedDigit())
            .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }

    private var detailText: String {
        let detail = transaction.kind == .expense
            ? store.categoryPath(for: transaction.categoryID)
            : transaction.kind.displayName
        return detail
    }

    private var iconName: String {
        if let categoryID = transaction.categoryID,
           let category = store.data.categories.first(where: { $0.id == categoryID }) {
            return category.systemImage
        }

        switch transaction.kind {
        case .expense:
            return "arrow.up.right"
        case .income:
            return "arrow.down.left"
        case .transfer:
            return "arrow.left.arrow.right"
        }
    }

    private var tint: Color {
        switch transaction.kind {
        case .expense:
            return PocketLedgerTheme.warning
        case .income:
            return PocketLedgerTheme.income
        case .transfer:
            return PocketLedgerTheme.positive
        }
    }
}

@MainActor
private struct AccountBalanceEditor: View {
    @ObservedObject var store: LedgerStore
    let account: Account

    @Environment(\.dismiss) private var dismiss
    @State private var balanceText: String
    @State private var recordAsTransaction = true
    @State private var note = ""
    @State private var errorMessage: String?

    init(store: LedgerStore, account: Account) {
        _store = ObservedObject(wrappedValue: store)
        self.account = account

        let currentBalance = store.balance(for: account)
        let amount = Decimal(currentBalance.minorUnits) / Decimal(account.currency.minorUnitScale)
        _balanceText = State(initialValue: NSDecimalNumber(decimal: amount).stringValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Current balance") {
                    LabeledContent("Now", value: store.balance(for: account).formatted)

                    TextField("New balance", text: $balanceText)
                        .keyboardType(.decimalPad)

                    Toggle("Count as transaction", isOn: $recordAsTransaction)

                    Text(recordAsTransaction
                         ? "Creates an income or expense adjustment in the transaction list."
                         : "Updates the opening balance without adding a transaction.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if recordAsTransaction {
                    Section("Transaction details") {
                        TextField("Note (optional)", text: $note)
                        Text("The adjustment uses the account's own currency and is marked Uncategorized.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .pocketScreen()
            .listRowBackground(.clear)
            .tint(PocketLedgerTheme.accent)
            .navigationTitle("Edit balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .alert("Balance not saved", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        guard let targetBalance = Money.parse(balanceText, currency: account.currency) else {
            errorMessage = "Enter a valid balance in \(account.currency.rawValue)."
            return
        }

        let saved = store.updateAccountBalance(
            accountID: account.id,
            targetBalance: targetBalance,
            recordAsTransaction: recordAsTransaction,
            note: note
        )
        guard saved else {
            errorMessage = "The persistent database is unavailable, so this balance was not changed."
            return
        }

        dismiss()
    }
}
