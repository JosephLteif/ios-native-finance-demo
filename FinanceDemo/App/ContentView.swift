import Foundation
import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var store = LedgerStore()
    @StateObject private var security = AppSecurityService()
    @State private var addAction: AddAction?
    @State private var isShowingAddMenu = false
    @State private var isUnlocked = false
    @State private var selectedTab: AppTab = .overview
    @State private var lastContentTab: AppTab = .overview
    @AppStorage(PocketLedgerTheme.colorThemeKey) private var selectedColorTheme = PocketLedgerColorTheme.ocean.rawValue
    @AppStorage(PocketLedgerTheme.appearanceModeKey) private var selectedAppearanceMode = PocketLedgerAppearanceMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if security.isPasscodeEnabled && !isUnlocked {
                AppLockView(security: security, isUnlocked: $isUnlocked)
            } else {
                unlockedContent
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                security.refresh()
                store.reload()
                store.processDueScheduledTransactions()
            } else if phase == .inactive || phase == .background {
                addAction = nil
                isShowingAddMenu = false
                if security.isPasscodeEnabled {
                    isUnlocked = false
                }
            }
        }
        .onChange(of: security.isPasscodeEnabled) { _, enabled in
            isUnlocked = !enabled
        }
        .task {
            store.processDueScheduledTransactions()
            await FinanceIntentIndexing.shared.refresh()
        }
    }

    private var unlockedContent: some View {
        TabView(selection: $selectedTab) {
            Tab("Overview", systemImage: "chart.bar.xaxis", value: .overview) {
                DashboardView(store: store)
            }

            Tab("Transactions", systemImage: "list.bullet.rectangle", value: .transactions) {
                TransactionsView(store: store)
            }

            Tab("Add", systemImage: "plus", value: .add, role: .prominent) {
                Color.clear
            }

            Tab("Metrics", systemImage: "chart.xyaxis.line", value: .metrics) {
                MetricsView(store: store)
            }

            Tab("More", systemImage: "ellipsis.circle", value: .more) {
                MoreView(store: store, security: security)
            }
        }
        .tint(PocketLedgerTheme.accent)
        .accessibilityIdentifier("pocket-ledger-\(selectedColorTheme)")
        .onChange(of: selectedTab) { _, tab in
            if tab == .add {
                selectedTab = lastContentTab
                isShowingAddMenu = true
            } else {
                lastContentTab = tab
            }
        }
        .preferredColorScheme(
            PocketLedgerAppearanceMode(rawValue: selectedAppearanceMode)?.preferredColorScheme
        )
        .confirmationDialog(
            "Add to your ledger",
            isPresented: $isShowingAddMenu,
            titleVisibility: .visible
        ) {
            Button("Scan bill", systemImage: "doc.text.viewfinder") {
                addAction = .scanBill
            }
            Button("Expense", systemImage: "arrow.up.right") {
                addAction = .expense
            }
            Button("Income", systemImage: "arrow.down.left") {
                addAction = .income
            }
            Button("Transfer", systemImage: "arrow.left.arrow.right") {
                addAction = .transfer
            }
            Button("Scheduled", systemImage: "calendar.badge.clock") {
                addAction = .scheduled
            }
        }
        .sheet(item: $addAction) { action in
            switch action {
            case .scanBill:
                BillScannerView(store: store)
            case .expense:
                TransactionEditor(store: store, initialKind: .expense)
            case .income:
                TransactionEditor(store: store, initialKind: .income)
            case .transfer:
                TransactionEditor(store: store, initialKind: .transfer)
            case .scheduled:
                TransactionEditor(store: store, initialKind: .expense, initialTiming: .scheduled)
            }
        }
    }

}

private enum AddAction: String, Identifiable {
    case scanBill
    case expense
    case income
    case transfer
    case scheduled

    var id: String { rawValue }
}

private enum AppTab: Hashable {
    case overview
    case transactions
    case add
    case metrics
    case more
}

@MainActor
private struct MoreView: View {
    @ObservedObject var store: LedgerStore
    @ObservedObject var security: AppSecurityService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ScheduledTransactionsView(store: store)
                    } label: {
                        Label("Scheduled", systemImage: "calendar.badge.clock")
                    }

                    NavigationLink {
                        AccountsView(store: store)
                    } label: {
                        Label("Accounts", systemImage: "wallet.pass")
                    }

                    NavigationLink {
                        CategoriesView(store: store)
                    } label: {
                        Label("Categories", systemImage: "square.grid.2x2")
                    }

                    NavigationLink {
                        ExchangeRatesView(store: store)
                    } label: {
                        Label("Exchange rates", systemImage: "arrow.left.arrow.right")
                    }

                    NavigationLink {
                        BudgetsView(store: store)
                    } label: {
                        Label("Budgets", systemImage: "chart.bar.doc.horizontal")
                    }

                    NavigationLink {
                        TemplatesView(store: store)
                    } label: {
                        Label("Templates", systemImage: "rectangle.stack")
                    }

                    NavigationLink {
                        SecuritySettingsView(store: store, security: security)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                } header: {
                    Text("Manage the rest of your ledger")
                }
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(PocketLedgerTheme.background)
        }
    }
}

@MainActor
private struct DashboardView: View {
    @ObservedObject var store: LedgerStore
    @AppStorage(PocketLedgerTheme.colorThemeKey) private var selectedColorTheme = PocketLedgerColorTheme.ocean.rawValue
    @AppStorage(PocketLedgerTheme.appearanceModeKey) private var selectedAppearanceMode = PocketLedgerAppearanceMode.system.rawValue

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    dashboardHeader
                    balanceHero
                    monthSnapshot
                    budgetSnapshot
                    recentActivity
                    storageNotice

                    if let status = store.lastActionStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(PocketLedgerTheme.textTertiary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .pocketScreen()
            .accessibilityIdentifier("dashboard-\(selectedColorTheme)")
            .preferredColorScheme(
                PocketLedgerAppearanceMode(rawValue: selectedAppearanceMode)?.preferredColorScheme
            )
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pocket Ledger")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Text(Date.now, style: .date)
                    .font(.subheadline)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
            }

            Spacer()
        }
    }

    private var balanceHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Available balance", systemImage: "wallet.pass.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PocketLedgerTheme.textSecondary)

                Spacer()

                Text("SEPARATE CURRENCIES")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(PocketLedgerTheme.textTertiary)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: LedgerCurrency.allCases.count),
                spacing: 12
            ) {
                ForEach(LedgerCurrency.allCases) { currency in
                    balanceColumn(for: currency)
                }
            }

            Text("Loans are tracked separately in Accounts.")
                .font(.caption)
                .foregroundStyle(PocketLedgerTheme.textTertiary)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [PocketLedgerTheme.surfaceElevated, PocketLedgerTheme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(PocketLedgerTheme.divider, lineWidth: 1)
        }
    }

    private func balanceColumn(for currency: LedgerCurrency) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(currency.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(currency == .usd ? PocketLedgerTheme.income : PocketLedgerTheme.textSecondary)

            Text(store.availableBalance(for: currency).formatted)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var monthSnapshot: some View {
        let expenses = store.monthlyExpenseTotals()

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "This month", detail: Date.now.formatted(.dateTime.month(.wide).year()))

            HStack(spacing: 10) {
                snapshotMetric(
                    title: "Transactions",
                    value: "\(store.monthTransactionCount)",
                    systemImage: "arrow.left.arrow.right",
                    tint: PocketLedgerTheme.income
                )

                snapshotMetric(
                    title: "Top category",
                    value: store.topCategoryThisMonth ?? "No activity",
                    systemImage: "tag.fill",
                    tint: PocketLedgerTheme.accent
                )
            }

            VStack(spacing: 0) {
                ForEach(LedgerCurrency.allCases.indices, id: \.self) { index in
                    if index > 0 {
                        Divider().overlay(PocketLedgerTheme.divider)
                    }
                    let currency = LedgerCurrency.allCases[index]
                    monthExpenseRow(currency: currency, total: expenses[currency] ?? 0)
                }
            }
            .padding(14)
            .background(PocketLedgerTheme.surface, in: RoundedRectangle(cornerRadius: 17))
        }
    }

    private func snapshotMetric(title: String, value: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(value)
                .font(.headline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(PocketLedgerTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(13)
        .background(PocketLedgerTheme.surface, in: RoundedRectangle(cornerRadius: 17))
    }

    private func monthExpenseRow(currency: LedgerCurrency, total: Int64) -> some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(PocketLedgerTheme.warning.opacity(0.18))
                    .frame(width: 8, height: 8)
                Text("Expenses in \(currency.rawValue)")
                    .font(.subheadline)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
            }

            Spacer()

            Text(Money(currency: currency, minorUnits: total).formatted)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(PocketLedgerTheme.warning)
        }
        .padding(.vertical, 5)
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Recent activity", detail: "Latest 5")

            if store.recentTransactions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundStyle(PocketLedgerTheme.textTertiary)
                    Text("Your ledger is ready")
                        .font(.headline)
                    Text("Add your first expense, income, or transfer to see it here.")
                        .font(.subheadline)
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .pocketCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.recentTransactions.prefix(5))) { transaction in
                        TransactionRow(
                            transaction: transaction,
                            store: store,
                            onEdit: {},
                            onDuplicate: {},
                            onDelete: {},
                            onSaveTemplate: {},
                            allowsActions: false
                        )
                        Divider().overlay(PocketLedgerTheme.divider)
                    }
                }
                .padding(.horizontal, 14)
                .background(PocketLedgerTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(PocketLedgerTheme.divider, lineWidth: 1)
                }
            }
        }
    }

    @ViewBuilder
    private var budgetSnapshot: some View {
        if !store.data.budgets.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionHeader(title: "Budget pulse", detail: "This month")
                    NavigationLink {
                        BudgetsView(store: store)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PocketLedgerTheme.textTertiary)
                    }
                    .accessibilityLabel("Open budgets")
                }

                VStack(spacing: 12) {
                    ForEach(Array(store.data.budgets.prefix(3))) { budget in
                        let spent = store.budgetSpent(budget)
                        let allowance = store.budgetAllowance(budget)
                        let over = spent.minorUnits > allowance.minorUnits
                        let ratio = min(
                            Double(spent.minorUnits) / Double(max(allowance.minorUnits, 1)),
                            1
                        )

                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(store.categoryPath(for: budget.categoryID))
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(spent.formatted) / \(allowance.formatted)")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(over ? PocketLedgerTheme.warning : PocketLedgerTheme.textSecondary)
                            }
                            ProgressView(value: ratio)
                                .tint(over ? PocketLedgerTheme.warning : PocketLedgerTheme.accent)
                        }
                    }
                }
                .padding(14)
                .background(PocketLedgerTheme.surface, in: RoundedRectangle(cornerRadius: 17))
            }
        }
    }

    private var storageNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: store.storageAvailable && store.sharedStorageAvailable
                  ? "checkmark.shield.fill"
                  : store.storageAvailable
                  ? "internaldrive.fill"
                  : "exclamationmark.triangle.fill")
            Text(store.storageStatus)
                .font(.caption)
            Spacer()
        }
        .foregroundStyle(store.storageAvailable
                          ? store.sharedStorageAvailable
                          ? PocketLedgerTheme.positive
                          : PocketLedgerTheme.accent
                          : PocketLedgerTheme.warning)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(PocketLedgerTheme.surface.opacity(0.72), in: Capsule())
    }

    private func sectionHeader(title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
            Spacer()
            Text(detail)
                .font(.caption.weight(.medium))
                .foregroundStyle(PocketLedgerTheme.textTertiary)
        }
    }
}

private enum TransactionFilter: String, CaseIterable, Identifiable, Hashable {
    case all = "All"
    case expense = "Expenses"
    case income = "Income"
    case transfer = "Transfers"

    var id: String { rawValue }

    var kind: TransactionKind? {
        switch self {
        case .all:
            return nil
        case .expense:
            return .expense
        case .income:
            return .income
        case .transfer:
            return .transfer
        }
    }
}

private struct TransactionDay: Identifiable {
    let date: Date
    let transactions: [LedgerTransaction]

    var id: Date { date }
}

@MainActor
private struct TransactionsView: View {
    @ObservedObject var store: LedgerStore
    @State private var selectedFilter: TransactionFilter = .all
    @State private var searchText = ""
    @State private var editingTransaction: LedgerTransaction?
    @State private var transactionToDelete: LedgerTransaction?
    @State private var transactionToTemplate: LedgerTransaction?
    @State private var isPresentingBillScanner = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    screenHeader

                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(TransactionFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Search transactions, categories, or accounts", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)

                    transactionsSummary

                    if groupedTransactions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "list.bullet.rectangle.portrait")
                                .font(.title2)
                                .foregroundStyle(PocketLedgerTheme.textTertiary)
                            Text("No transactions yet")
                                .font(.headline)
                            Text("Start with a quick expense from the plus button.")
                                .font(.subheadline)
                                .foregroundStyle(PocketLedgerTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 38)
                    } else {
                        ForEach(groupedTransactions) { day in
                            VStack(alignment: .leading, spacing: 0) {
                                dayHeader(day)

                                VStack(spacing: 0) {
                                    ForEach(day.transactions) { transaction in
                                        TransactionRow(
                                            transaction: transaction,
                                            store: store,
                                            onEdit: { editingTransaction = transaction },
                                            onDuplicate: { _ = store.duplicateTransaction(id: transaction.id) },
                                            onDelete: { transactionToDelete = transaction },
                                            onSaveTemplate: { transactionToTemplate = transaction },
                                            allowsActions: true
                                        )
                                        Divider().overlay(PocketLedgerTheme.divider)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .background(PocketLedgerTheme.surface, in: RoundedRectangle(cornerRadius: 18))
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
            .pocketScreen()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isPresentingBillScanner) {
                BillScannerView(store: store)
            }
            .sheet(item: $editingTransaction) { transaction in
                TransactionEditor(store: store, transaction: transaction)
            }
            .sheet(item: $transactionToTemplate) { transaction in
                TemplateNameEditor(store: store, transaction: transaction)
            }
            .confirmationDialog(
                "Delete transaction?",
                isPresented: Binding(
                    get: { transactionToDelete != nil },
                    set: { if !$0 { transactionToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let transactionToDelete {
                        _ = store.deleteTransaction(id: transactionToDelete.id)
                    }
                    self.transactionToDelete = nil
                }
                Button("Cancel", role: .cancel) { transactionToDelete = nil }
            } message: {
                Text(transactionToDelete?.note ?? "")
            }
        }
    }

    private var screenHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Transactions")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Text("Every inflow and outflow, in one place")
                    .font(.subheadline)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
            }

            Spacer()

            Button {
                isPresentingBillScanner = true
            } label: {
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(PocketLedgerTheme.background)
                    .frame(width: 42, height: 42)
                    .background(PocketLedgerTheme.positive, in: Circle())
            }
            .accessibilityLabel("Scan bill")

        }
    }

    private var filteredTransactions: [LedgerTransaction] {
        store.recentTransactions.filter { transaction in
            let matchesKind = selectedFilter.kind.map { transaction.kind == $0 } ?? true
            guard matchesKind else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            let accountNames = (transaction.outflows + transaction.inflows)
                .compactMap { store.account(with: $0.accountID)?.name }
                .joined(separator: " ")
            let searchable = [
                transaction.note,
                store.categoryPath(for: transaction.categoryID),
                accountNames,
                transaction.kind.displayName
            ].joined(separator: " ")
            return searchable.localizedCaseInsensitiveContains(query)
        }
    }

    private var groupedTransactions: [TransactionDay] {
        let grouped = Dictionary(grouping: filteredTransactions) {
            Calendar.current.startOfDay(for: $0.date)
        }

        return grouped.keys.sorted(by: >).map { date in
            TransactionDay(date: date, transactions: grouped[date] ?? [])
        }
    }

    private var transactionsSummary: some View {
        let expenses = store.monthlyExpenseTotals()

        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Date.now.formatted(.dateTime.month(.wide).year()))
                        .font(.headline)
                    Text("Monthly overview")
                        .font(.caption)
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                }

                Spacer()

                Text("\(filteredTransactions.count) shown")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PocketLedgerTheme.textTertiary)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: LedgerCurrency.allCases.count),
                spacing: 10
            ) {
                ForEach(LedgerCurrency.allCases) { currency in
                    transactionSummaryMetric(
                        title: "\(currency.rawValue) spent",
                        value: Money(currency: currency, minorUnits: expenses[currency] ?? 0).formatted
                    )
                }
            }
        }
        .pocketCard()
    }

    private func transactionSummaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.weight(.semibold).monospacedDigit())
                .foregroundStyle(PocketLedgerTheme.warning)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(PocketLedgerTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayHeader(_ day: TransactionDay) -> some View {
        HStack(spacing: 11) {
            VStack(spacing: 0) {
                Text(day.date.formatted(.dateTime.day()))
                    .font(.title3.weight(.bold))
                Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
            }
            .frame(width: 46, height: 46)
            .background(PocketLedgerTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 2) {
                Text(day.date, style: .date)
                    .font(.subheadline.weight(.semibold))
                Text("\(day.transactions.count) \(day.transactions.count == 1 ? "transaction" : "transactions")")
                    .font(.caption)
                    .foregroundStyle(PocketLedgerTheme.textTertiary)
            }

            Spacer()
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

@MainActor
private struct TransactionRow: View {
    let transaction: LedgerTransaction
    @ObservedObject var store: LedgerStore
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onSaveTemplate: () -> Void
    let allowsActions: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 38, height: 38)
                .background(accentColor.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.note)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(rowSubtitle)
                    .font(.caption)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                    .lineLimit(1)

                if let amountDue = transaction.amountDue {
                    Text("Bill total · \(amountDue.formatted)")
                        .font(.caption2)
                        .foregroundStyle(PocketLedgerTheme.textTertiary)
                        .lineLimit(1)
                }

                if let exchangeRate = transaction.exchangeRate {
                    Text(exchangeRate.summary)
                        .font(.caption2)
                        .foregroundStyle(PocketLedgerTheme.textTertiary)
                        .lineLimit(1)
                }

                if let shortfall = transaction.changeAdjustment?.shortfall {
                    Text(shortfall.minorUnits > 0
                         ? "Change short · \(shortfall.formatted)"
                         : "Change adjusted · \(shortfall.formatted)")
                        .font(.caption2)
                        .foregroundStyle(PocketLedgerTheme.warning)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(amountText)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(accentColor)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .contextMenu {
            if allowsActions {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
                Button("Save as template", systemImage: "rectangle.stack.badge.plus", action: onSaveTemplate)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
    }

    private var rowSubtitle: String {
        let detail = transaction.kind == .expense
            ? store.categoryPath(for: transaction.categoryID)
            : transaction.kind.displayName
        return "\(detail) · \(transaction.date.formatted(date: .omitted, time: .shortened))"
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

    private var accentColor: Color {
        switch transaction.kind {
        case .expense:
            return PocketLedgerTheme.warning
        case .income:
            return PocketLedgerTheme.income
        case .transfer:
            return PocketLedgerTheme.positive
        }
    }

    private var amountText: String {
        switch transaction.kind {
        case .expense:
            return "− " + transaction.outflows.map { $0.money.formatted }.joined(separator: " + ")
        case .income:
            return "+ " + transaction.inflows.map { $0.money.formatted }.joined(separator: " + ")
        case .transfer:
            return store.transactionSummary(transaction)
        }
    }
}

@MainActor
private struct AccountsView: View {
    @ObservedObject var store: LedgerStore
    @State private var isPresentingAccount = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    screenHeader

                    ForEach(LedgerCurrency.allCases) { currency in
                        let accounts = store.data.accounts.filter { $0.currency == currency }
                        if !accounts.isEmpty {
                            accountSection(currency: currency, accounts: accounts)
                        }
                    }

                    Text(store.storageAvailable && store.sharedStorageAvailable
                         ? "Stored locally in the shared app container."
                         : store.storageAvailable
                         ? "Stored persistently on this device; widget sharing is unavailable."
                         : "Persistent storage is unavailable; changes cannot be saved.")
                        .font(.caption)
                        .foregroundStyle(PocketLedgerTheme.textTertiary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .pocketScreen()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isPresentingAccount) {
                AccountEditor(store: store)
            }
        }
    }

    private var screenHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Accounts")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Text("Tap an account for activity and balance tools")
                    .font(.subheadline)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
            }

            Spacer()

            Button {
                isPresentingAccount = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(PocketLedgerTheme.background)
                    .frame(width: 42, height: 42)
                    .background(PocketLedgerTheme.accent, in: Circle())
            }
            .accessibilityLabel("Add account")
        }
    }

    private func accountSection(currency: LedgerCurrency, accounts: [Account]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Text(currency.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(currency == .usd ? PocketLedgerTheme.income : PocketLedgerTheme.textSecondary)
                    Text(currency.displayName)
                        .font(.caption)
                        .foregroundStyle(PocketLedgerTheme.textTertiary)
                }

                Spacer()

                Text(Money(
                    currency: currency,
                    minorUnits: accounts
                        .filter(\.includeInTotals)
                        .reduce(Int64.zero) { $0 + store.balance(for: $1).minorUnits }
                ).formatted)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
            }

            VStack(spacing: 0) {
                ForEach(accounts) { account in
                    NavigationLink {
                        AccountDetailView(store: store, accountID: account.id)
                    } label: {
                        AccountRow(account: account, balance: store.balance(for: account))
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(PocketLedgerTheme.divider)
                }
            }
            .padding(.horizontal, 14)
            .background(PocketLedgerTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(PocketLedgerTheme.divider, lineWidth: 1)
            }
        }
    }
}

@MainActor
private struct AccountRow: View {
    let account: Account
    let balance: Money

    var body: some View {
        HStack(spacing: 12) {
            PocketIcon(
                systemImage: account.type.systemImage,
                tint: account.type == .loan || !account.includeInTotals
                    ? PocketLedgerTheme.warning
                    : PocketLedgerTheme.income,
                size: 36
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.subheadline.weight(.semibold))
                Text(account.type.displayName)
                    .font(.caption)
                    .foregroundStyle(PocketLedgerTheme.textTertiary)
                if !account.includeInTotals {
                    Text("Excluded from totals")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(PocketLedgerTheme.warning)
                }
            }

            Spacer()

            Text(balance.formatted)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(account.type == .loan || !account.includeInTotals
                    ? PocketLedgerTheme.warning
                    : PocketLedgerTheme.textPrimary)
        }
        .padding(.vertical, 11)
    }
}

@MainActor
private struct CategoriesView: View {
    @ObservedObject var store: LedgerStore
    @State private var isPresentingCategory = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    screenHeader

                    ForEach(store.rootCategories) { parent in
                        categoryGroup(parent)
                    }

                    if store.rootCategories.isEmpty {
                        Text("Add a top-level category to organize your transactions.")
                            .font(.subheadline)
                            .foregroundStyle(PocketLedgerTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pocketCard()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .pocketScreen()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isPresentingCategory) {
                CategoryEditor(store: store)
            }
        }
    }

    private var screenHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Categories")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Text("Make every expense easy to understand")
                    .font(.subheadline)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
            }

            Spacer()

            Button {
                isPresentingCategory = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(PocketLedgerTheme.background)
                    .frame(width: 42, height: 42)
                    .background(PocketLedgerTheme.accent, in: Circle())
            }
            .accessibilityLabel("Add category")
        }
    }

    private func categoryGroup(_ parent: LedgerCategory) -> some View {
        let children = store.data.categories.filter { $0.parentID == parent.id }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                PocketIcon(systemImage: parent.systemImage, tint: PocketLedgerTheme.accent, size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(parent.name)
                        .font(.headline)
                    Text(children.isEmpty ? "Top-level category" : "\(children.count) subcategories")
                        .font(.caption)
                        .foregroundStyle(PocketLedgerTheme.textTertiary)
                }

                Spacer()
            }

            if children.isEmpty {
                Text("No subcategories yet")
                    .font(.caption)
                    .foregroundStyle(PocketLedgerTheme.textTertiary)
                    .padding(.top, 4)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(children) { child in
                        CategoryTile(category: child)
                    }
                }
            }
        }
        .pocketCard()
    }
}

private struct CategoryTile: View {
    let category: LedgerCategory

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: category.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PocketLedgerTheme.textSecondary)
            Text(category.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(PocketLedgerTheme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .padding(.horizontal, 4)
        .background(PocketLedgerTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 13))
    }
}

@MainActor
private struct AccountEditor: View {
    @ObservedObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type: AccountType = .cash
    @State private var currency: LedgerCurrency = .usd
    @State private var openingBalance = "0"
    @State private var includeInTotals = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases) { accountType in
                            Label(accountType.displayName, systemImage: accountType.systemImage)
                                .tag(accountType)
                        }
                    }
                    Picker("Currency", selection: $currency) {
                        ForEach(LedgerCurrency.allCases) { currency in
                            Text(currency.rawValue).tag(currency)
                        }
                    }
                    Toggle("Include in totals and metrics", isOn: $includeInTotals)
                    Text("Turn this off for assets or investments you want to track separately.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Opening balance") {
                    TextField("Amount", text: $openingBalance)
                        .keyboardType(.decimalPad)
                    Text("The amount is stored in the account's own currency.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PocketLedgerTheme.background)
            .listRowBackground(PocketLedgerTheme.surface)
            .tint(PocketLedgerTheme.accent)
            .navigationTitle("New account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .alert("Account not saved", isPresented: errorPresented) {
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
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter an account name."
            return
        }
        guard let balance = Money.parse(openingBalance, currency: currency) else {
            errorMessage = "Enter a valid opening balance."
            return
        }

        store.addAccount(
            Account(
                name: trimmedName,
                type: type,
                currency: currency,
                openingBalance: balance,
                includeInTotals: includeInTotals
            )
        )
        dismiss()
    }
}

@MainActor
private struct CategoryEditor: View {
    @ObservedObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var parentID: UUID?
    @State private var systemImage = "tag"
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    TextField("Name", text: $name)
                    Picker("Parent category", selection: $parentID) {
                        Text("Top-level category").tag(UUID?.none)
                        ForEach(store.rootCategories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    TextField("SF Symbol", text: $systemImage)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PocketLedgerTheme.background)
            .listRowBackground(PocketLedgerTheme.surface)
            .tint(PocketLedgerTheme.accent)
            .navigationTitle("New category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .alert("Category not saved", isPresented: errorPresented) {
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
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a category name."
            return
        }

        let trimmedSymbol = systemImage.trimmingCharacters(in: .whitespacesAndNewlines)
        store.addCategory(
            LedgerCategory(
                name: trimmedName,
                parentID: parentID,
                systemImage: trimmedSymbol.isEmpty ? "tag" : trimmedSymbol
            )
        )
        dismiss()
    }
}

private struct MovementDraft: Identifiable {
    let id = UUID()
    var accountID: UUID
    var amount: String
}

@MainActor
private struct MovementLineEditor: View {
    @ObservedObject var store: LedgerStore
    @Binding var line: MovementDraft
    let amountPlaceholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Account", selection: $line.accountID) {
                ForEach(store.data.accounts) { account in
                    Text("\(account.name) (\(account.currency.rawValue))")
                        .tag(account.id)
                }
            }

            HStack {
                TextField(amountPlaceholder, text: $line.amount)
                    .keyboardType(.decimalPad)
                if let account = store.account(with: line.accountID) {
                    Text(account.currency.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

@MainActor
struct TransactionEditor: View {
    @ObservedObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var date = Date.now
    @State private var kind: TransactionKind = .expense
    @State private var timing: TransactionTiming = .now
    @State private var scheduleFrequency: ScheduleFrequency = .once
    @State private var scheduleEnabled = true
    @State private var categoryID: UUID?
    @State private var dueCurrency: LedgerCurrency = .usd
    @State private var amountDue = ""
    @State private var outflows: [MovementDraft]
    @State private var inflows: [MovementDraft] = []
    @State private var requestedChange = ""
    @State private var useCustomRate = true
    @State private var rateBase: LedgerCurrency = .usd
    @State private var rateQuote: LedgerCurrency = .lbp
    @State private var rateText = "100000"
    @State private var errorMessage: String?
    private let editingScheduleID: UUID?
    private let editingScheduleLastRunDate: Date?
    private let editingScheduleNextRunDate: Date?
    private let editingScheduleFrequency: ScheduleFrequency?
    private let editingTransactionID: UUID?

    init(
        store: LedgerStore,
        initialKind: TransactionKind = .expense,
        initialAmount: Money? = nil,
        initialBillTotal: Money? = nil,
        initialNote: String? = nil,
        initialTiming: TransactionTiming = .now,
        initialFrequency: ScheduleFrequency = .once,
        scheduledTransaction: ScheduledTransaction? = nil,
        transaction: LedgerTransaction? = nil,
        template: LedgerTemplate? = nil
    ) {
        _store = ObservedObject(wrappedValue: store)
        let sourceTransaction = transaction ?? template?.transactionTemplate
        let preferredCurrency = sourceTransaction?.outflows.first?.money.currency
            ?? sourceTransaction?.inflows.first?.money.currency
            ?? scheduledTransaction?.outflows.first?.money.currency
            ?? scheduledTransaction?.inflows.first?.money.currency
            ?? initialAmount?.currency
            ?? scheduledTransaction?.amountDue?.currency
            ?? initialBillTotal?.currency
        let firstAccount = store.data.accounts.first { account in
            guard let preferredCurrency else { return true }
            return account.currency == preferredCurrency
        } ?? store.data.accounts.first
        let firstAccountID = firstAccount?.id ?? UUID()
        let amountDue = sourceTransaction?.amountDue ?? scheduledTransaction?.amountDue ?? initialBillTotal
        let initialCurrencies = LedgerCurrency.allCases.filter { currency in
            (sourceTransaction?.outflows ?? scheduledTransaction?.outflows ?? []).contains { $0.money.currency == currency }
                || (sourceTransaction?.inflows ?? scheduledTransaction?.inflows ?? []).contains { $0.money.currency == currency }
        }
        let initialRateBase = sourceTransaction?.exchangeRate?.baseCurrency
            ?? scheduledTransaction?.exchangeRate?.baseCurrency
            ?? initialCurrencies.first
            ?? .usd
        let initialRateQuote = sourceTransaction?.exchangeRate?.quoteCurrency
            ?? scheduledTransaction?.exchangeRate?.quoteCurrency
            ?? initialCurrencies.first(where: { $0 != initialRateBase })
            ?? (initialRateBase == .usd ? .lbp : .usd)
        let initialSavedRate = sourceTransaction?.exchangeRate
            ?? scheduledTransaction?.exchangeRate
            ?? store.exchangeRate(base: initialRateBase, quote: initialRateQuote)
        _note = State(initialValue: sourceTransaction?.note ?? scheduledTransaction?.note ?? initialNote ?? "")
        _date = State(initialValue: transaction?.date ?? scheduledTransaction?.nextRunDate ?? .now)
        _kind = State(initialValue: sourceTransaction?.kind ?? scheduledTransaction?.kind ?? initialKind)
        _timing = State(initialValue: transaction == nil && scheduledTransaction == nil ? initialTiming : transaction == nil ? .scheduled : .now)
        _scheduleFrequency = State(initialValue: scheduledTransaction?.frequency ?? initialFrequency)
        _scheduleEnabled = State(initialValue: scheduledTransaction?.isEnabled ?? true)
        _dueCurrency = State(initialValue: amountDue?.currency ?? preferredCurrency ?? .usd)
        _amountDue = State(initialValue: amountDue.map { Self.inputText(for: $0) } ?? "")
        _outflows = State(
            initialValue: (sourceTransaction?.outflows ?? scheduledTransaction?.outflows)?.map {
                MovementDraft(accountID: $0.accountID, amount: Self.inputText(for: $0.money))
            } ?? [
                MovementDraft(
                    accountID: firstAccountID,
                    amount: initialAmount.map { Self.inputText(for: $0) } ?? ""
                )
            ]
        )
        _inflows = State(
            initialValue: (sourceTransaction?.inflows ?? scheduledTransaction?.inflows)?.map {
                MovementDraft(accountID: $0.accountID, amount: Self.inputText(for: $0.money))
            } ?? []
        )
        _requestedChange = State(
            initialValue: (sourceTransaction?.changeAdjustment ?? scheduledTransaction?.changeAdjustment).map { Self.inputText(for: $0.requested) } ?? ""
        )
        _rateBase = State(initialValue: initialRateBase)
        _rateQuote = State(initialValue: initialRateQuote)
        _rateText = State(
            initialValue: initialSavedRate.map {
                NSDecimalNumber(decimal: $0.quoteUnitsPerBaseUnit).stringValue
            } ?? "100000"
        )
        _categoryID = State(
            initialValue: sourceTransaction?.categoryID
                ?? scheduledTransaction?.categoryID
                ?? store.data.categories.first(where: { $0.parentID != nil })?.id
                ?? store.data.categories.first?.id
        )
        editingScheduleID = scheduledTransaction?.id
        editingScheduleLastRunDate = scheduledTransaction?.lastRunDate
        editingScheduleNextRunDate = scheduledTransaction?.nextRunDate
        editingScheduleFrequency = scheduledTransaction?.frequency
        editingTransactionID = transaction?.id
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(TransactionKind.allCases) { transactionKind in
                            Text(transactionKind.displayName).tag(transactionKind)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Transaction type")
                }

                Section("Timing") {
                    Picker("When", selection: $timing) {
                        ForEach(TransactionTiming.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isEditingScheduledTransaction)

                    if timing == .scheduled {
                        DatePicker("First run", selection: $date, displayedComponents: .date)

                        Picker("Repeats", selection: $scheduleFrequency) {
                            ForEach(ScheduleFrequency.allCases) { frequency in
                                Text(frequency.displayName).tag(frequency)
                            }
                        }

                        Toggle("Enabled", isOn: $scheduleEnabled)
                            .disabled(completedOneTimeSchedule)

                        if completedOneTimeSchedule {
                            Text("This one-time schedule has already been added to transactions.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    }
                }

                Section("Details") {
                    TextField("What was this for?", text: $note)

                    if kind == .expense {
                        if store.data.categories.isEmpty {
                            Text("No categories yet — this expense will be Uncategorized.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Category", selection: $categoryID) {
                                Text("Uncategorized").tag(UUID?.none)
                                ForEach(store.data.categories) { category in
                                    Text(store.categoryPath(for: category.id))
                                        .tag(Optional(category.id))
                                }
                            }
                        }
                        Picker("Bill currency", selection: $dueCurrency) {
                            ForEach(LedgerCurrency.allCases) { currency in
                                Text(currency.rawValue).tag(currency)
                            }
                        }
                        TextField("Bill total (optional)", text: $amountDue)
                            .keyboardType(.decimalPad)
                    }
                }

                if kind != .income {
                    Section {
                        ForEach($outflows) { $line in
                            MovementLineEditor(
                                store: store,
                                line: $line,
                                amountPlaceholder: "Amount leaving account"
                            )
                        }
                        .onDelete { outflows.remove(atOffsets: $0) }

                        Button {
                            outflows.append(newMovementDraft)
                        } label: {
                            Label("Add another account", systemImage: "plus.circle")
                        }
                    } header: {
                        Text("Money leaving accounts")
                    } footer: {
                        Text("Use one line for each currency or account used to pay.")
                    }
                }

                Section {
                    if inflows.isEmpty {
                        Button {
                            inflows.append(newMovementDraft)
                        } label: {
                            Label(
                                kind == .expense ? "Add returned money" : "Add receiving account",
                                systemImage: "arrow.down.circle"
                            )
                        }
                    } else {
                        ForEach($inflows) { $line in
                            MovementLineEditor(
                                store: store,
                                line: $line,
                                amountPlaceholder: "Amount entering account"
                            )
                        }
                        .onDelete { inflows.remove(atOffsets: $0) }

                        Button {
                            inflows.append(newMovementDraft)
                        } label: {
                            Label("Add another receiving account", systemImage: "plus.circle")
                        }

                        if kind == .expense && inflows.count == 1 {
                            TextField("Requested change (optional)", text: $requestedChange)
                                .keyboardType(.decimalPad)
                            if let preview = shortfallPreview {
                                Text(preview)
                                    .font(.footnote)
                                    .foregroundStyle(PocketLedgerTheme.warning)
                            }
                        }
                    }
                } header: {
                    Text(kind == .expense ? "Change / money returned" : "Money entering accounts")
                } footer: {
                    Text(kind == .expense
                         ? "Returned money may go to a different account and currency than the payment."
                         : "Choose the account and currency receiving the money.")
                }

                if selectedCurrencies.count > 1 {
                    Section("Exchange rate") {
                        Toggle("Use a custom rate", isOn: $useCustomRate)

                        if useCustomRate {
                            Picker("Base", selection: $rateBase) {
                                ForEach(LedgerCurrency.allCases) { currency in
                                    Text(currency.rawValue).tag(currency)
                                }
                            }
                            Picker("Quote", selection: $rateQuote) {
                                ForEach(LedgerCurrency.allCases) { currency in
                                    Text(currency.rawValue).tag(currency)
                                }
                            }
                            TextField("Quote units per base unit", text: $rateText)
                                .keyboardType(.decimalPad)

                            if let savedRate {
                                Button {
                                    rateText = NSDecimalNumber(decimal: savedRate.quoteUnitsPerBaseUnit).stringValue
                                } label: {
                                    Label("Use saved rate: \(savedRate.summary)", systemImage: "arrow.clockwise")
                                }
                            }

                            Text("Enter how many \(rateQuote.rawValue) equal 1 \(rateBase.rawValue).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onChange(of: selectedCurrencies) { _, currencies in
                guard currencies.count > 1,
                      !currencies.contains(rateBase) || !currencies.contains(rateQuote) else {
                    return
                }
                rateBase = currencies[0]
                rateQuote = currencies[1]
                if let savedRate {
                    rateText = NSDecimalNumber(decimal: savedRate.quoteUnitsPerBaseUnit).stringValue
                }
            }
            .scrollContentBackground(.hidden)
            .background(PocketLedgerTheme.background)
            .listRowBackground(PocketLedgerTheme.surface)
            .tint(PocketLedgerTheme.accent)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonTitle, action: save)
                        .disabled(!canSave)
                }
            }
            .alert("Transaction not saved", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var isEditingScheduledTransaction: Bool {
        editingScheduleID != nil
    }

    private var completedOneTimeSchedule: Bool {
        isEditingScheduledTransaction
            && editingScheduleLastRunDate != nil
            && scheduleFrequency == .once
            && (editingScheduleNextRunDate.map { Calendar.current.isDate(date, inSameDayAs: $0) } ?? false)
    }

    private var navigationTitle: String {
        if isEditingScheduledTransaction {
            return "Edit schedule"
        }
        if editingTransactionID != nil {
            return "Edit transaction"
        }
        return timing == .scheduled ? "Schedule transaction" : "New transaction"
    }

    private var saveButtonTitle: String {
        if timing == .scheduled {
            return isEditingScheduledTransaction ? "Update" : "Schedule"
        }
        return editingTransactionID == nil ? "Save" : "Update"
    }

    private var newMovementDraft: MovementDraft {
        MovementDraft(accountID: store.data.accounts.first?.id ?? UUID(), amount: "")
    }

    private static func inputText(for money: Money) -> String {
        let amount = Decimal(money.minorUnits) / Decimal(money.currency.minorUnitScale)
        return NSDecimalNumber(decimal: amount).stringValue
    }

    private var selectedCurrencies: [LedgerCurrency] {
        let accountIDs = (kind == .income ? [] : outflows.map(\.accountID)) + inflows.map(\.accountID)
        let currencies = Set(accountIDs.compactMap { store.account(with: $0)?.currency })
        return LedgerCurrency.allCases.filter { currencies.contains($0) }
    }

    private var savedRate: ExchangeRate? {
        store.exchangeRate(base: rateBase, quote: rateQuote)
    }

    private var parsedOutflows: [MoneyMovement]? {
        guard kind != .income else { return [] }
        return parseMovements(outflows)
    }

    private var parsedInflows: [MoneyMovement]? {
        parseMovements(inflows)
    }

    private var canSave: Bool {
        guard let parsedOutflows,
              let parsedInflows,
              !parsedOutflows.isEmpty || !parsedInflows.isEmpty else {
            return false
        }

        switch kind {
        case .expense:
            guard !parsedOutflows.isEmpty else { return false }
        case .income:
            guard !parsedInflows.isEmpty else { return false }
        case .transfer:
            guard !parsedOutflows.isEmpty, !parsedInflows.isEmpty else { return false }
        }

        if kind == .expense,
           inflows.count == 1,
           !requestedChange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard parsedInflows.count == 1,
                  let currency = store.account(with: inflows[0].accountID)?.currency,
                  let requested = Money.parse(requestedChange, currency: currency),
                  requested.minorUnits >= 0 else {
                return false
            }
        }

        if !amountDue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard kind == .expense,
                  let due = Money.parse(amountDue, currency: dueCurrency),
                  due.minorUnits > 0 else {
                return false
            }
        }

        if selectedCurrencies.count > 1 && useCustomRate {
            guard rateBase != rateQuote,
                  selectedCurrencies.contains(rateBase),
                  selectedCurrencies.contains(rateQuote),
                  let rate = Decimal(string: rateText.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")),
                  rate > 0 else {
                return false
            }
        }

        return true
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var shortfallPreview: String? {
        guard inflows.count == 1,
              let account = store.account(with: inflows[0].accountID),
              let requested = Money.parse(requestedChange, currency: account.currency),
              let actual = Money.parse(inflows[0].amount, currency: account.currency) else {
            return nil
        }

        let difference = requested.minorUnits - actual.minorUnits
        if difference > 0 {
            return "Recorded denomination shortfall: \(Money(currency: account.currency, minorUnits: difference).formatted)."
        }
        if difference < 0 {
            return "Actual change is \(Money(currency: account.currency, minorUnits: -difference).formatted) above the requested amount."
        }
        return "The requested and actual change match."
    }

    private func parseMovements(_ drafts: [MovementDraft]) -> [MoneyMovement]? {
        let movements = drafts.compactMap { draft -> MoneyMovement? in
            guard let account = store.account(with: draft.accountID),
                  let money = Money.parse(draft.amount, currency: account.currency),
                  money.minorUnits > 0 else {
                return nil
            }
            return MoneyMovement(accountID: account.id, money: money)
        }
        return movements.count == drafts.count ? movements : nil
    }

    private func save() {
        guard let parsedOutflows, let parsedInflows else {
            errorMessage = "Enter a valid amount for every account line."
            return
        }

        var exchangeRate: ExchangeRate?
        if selectedCurrencies.count > 1 && useCustomRate {
            guard rateBase != rateQuote,
                  selectedCurrencies.contains(rateBase),
                  selectedCurrencies.contains(rateQuote),
                  let rate = Decimal(string: rateText.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")),
                  rate > 0 else {
                errorMessage = "Enter a positive custom exchange rate with different currencies."
                return
            }
            exchangeRate = ExchangeRate(
                baseCurrency: rateBase,
                quoteCurrency: rateQuote,
                quoteUnitsPerBaseUnit: rate
            )
        }

        var changeAdjustment: ChangeAdjustment?
        if kind == .expense,
           !requestedChange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           parsedInflows.count == 1,
           let currency = store.account(with: inflows[0].accountID)?.currency,
           let requested = Money.parse(requestedChange, currency: currency) {
            changeAdjustment = ChangeAdjustment(requested: requested, actual: parsedInflows[0].money)
        }

        var parsedAmountDue: Money?
        if !amountDue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard kind == .expense,
                  let value = Money.parse(amountDue, currency: dueCurrency),
                  value.minorUnits > 0 else {
                errorMessage = "Enter a valid bill total."
                return
            }
            parsedAmountDue = value
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let transaction = LedgerTransaction(
            id: editingTransactionID ?? UUID(),
            date: date,
            note: trimmedNote.isEmpty ? kind.displayName : trimmedNote,
            kind: kind,
            categoryID: kind == .expense ? categoryID : nil,
            amountDue: parsedAmountDue,
            outflows: parsedOutflows,
            inflows: parsedInflows,
            exchangeRate: exchangeRate,
            changeAdjustment: changeAdjustment
        )

        if timing == .scheduled {
            let dateChanged = editingScheduleNextRunDate.map {
                !Calendar.current.isDate(date, inSameDayAs: $0)
            } ?? false
            let frequencyChanged = editingScheduleFrequency.map { $0 != scheduleFrequency } ?? false
            let lastRunDate = dateChanged || frequencyChanged ? nil : editingScheduleLastRunDate
            let enabled = lastRunDate != nil && scheduleFrequency == .once
                ? false
                : scheduleEnabled
            let scheduledTransaction = ScheduledTransaction(
                id: editingScheduleID ?? UUID(),
                nextRunDate: date,
                frequency: scheduleFrequency,
                isEnabled: enabled,
                lastRunDate: lastRunDate,
                note: transaction.note,
                kind: transaction.kind,
                categoryID: transaction.categoryID,
                amountDue: transaction.amountDue,
                outflows: transaction.outflows,
                inflows: transaction.inflows,
                exchangeRate: transaction.exchangeRate,
                changeAdjustment: transaction.changeAdjustment
            )

            if editingScheduleID != nil {
                guard store.updateScheduledTransaction(scheduledTransaction) else { return }
            } else {
                store.addScheduledTransaction(scheduledTransaction)
            }
        } else {
            if editingTransactionID == nil {
                store.addTransaction(transaction)
            } else {
                guard store.updateTransaction(transaction) else { return }
            }
        }
        dismiss()
    }
}
