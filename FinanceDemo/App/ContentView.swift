import AppIntents
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ContentView: View {
    @StateObject private var store = LedgerStore()
    @StateObject private var security = AppSecurityService()
    @StateObject private var intentSearchRouter = FinanceIntentSearchRouter.shared
    @State private var addAction: AddAction?
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var tabBeforeSearch = AppTab.overview
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isShowingSetup = false
    @State private var isShowingImportWizardUITest = false
    @State private var isUnlocked = false
    @SceneStorage("pocketLedger.selectedTab") private var selectedTabRawValue = AppTab.overview.rawValue
    @AppStorage(SetupWizardView.completedKey) private var setupCompleted = false
    @AppStorage(PocketLedgerTheme.appearanceModeKey) private var selectedAppearanceMode = PocketLedgerAppearanceMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            unlockedContent
                .allowsHitTesting(!(security.isPasscodeEnabled && !isUnlocked))

            if security.isPasscodeEnabled && !isUnlocked {
                AppLockView(security: security, isUnlocked: $isUnlocked)
                    .zIndex(1)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                security.refresh()
                store.reload()
                store.processDueScheduledTransactions()
                let schedules = store.data.scheduledTransactions
                Task {
                    await NotificationService.refreshScheduledTransactionNotifications(
                        schedules: schedules
                    )
                }
            } else if phase == .inactive {
                if security.isPasscodeEnabled && !security.isBiometricPromptActive {
                    isUnlocked = false
                }
            } else if phase == .background, security.isPasscodeEnabled {
                isUnlocked = false
            }
        }
        .onChange(of: security.isPasscodeEnabled) { _, enabled in
            isUnlocked = !enabled
        }
        .onChange(of: intentSearchRouter.pendingSearch?.id) { _, _ in
            openPendingIntentSearch()
        }
        .task {
            openPendingIntentSearch()
            if ProcessInfo.processInfo.arguments.contains("-ImportWizardUITest") {
                isShowingImportWizardUITest = true
                return
            }
            store.processDueScheduledTransactions()
            await NotificationService.refreshScheduledTransactionNotifications(
                schedules: store.data.scheduledTransactions
            )
            await FinanceIntentIndexing.shared.refresh()
            if !setupCompleted && store.data.accounts.isEmpty && store.data.categories.isEmpty {
                isShowingSetup = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pocketLedgerWatchLedgerDidChange)) { _ in
            store.reload()
        }
        .onOpenURL(perform: handleDeepLink)
        .sheet(isPresented: $isShowingSetup) {
            SetupWizardView(store: store)
        }
        .sheet(isPresented: $isShowingImportWizardUITest) {
            ImportWizardView(store: store, document: importWizardUITestDocument)
                .presentationDetents([.large])
        }
    }

    private var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: {
                let tab = AppTab(rawValue: selectedTabRawValue) ?? .overview
                return tab == .metrics ? .more : tab
            },
            set: { tab in
                guard selectedTabRawValue != tab.rawValue else { return }
                let currentTab = AppTab(rawValue: selectedTabRawValue) ?? .overview
                if tab == .search, currentTab != .search {
                    tabBeforeSearch = currentTab
                } else if tab != .search {
                    isSearchPresented = false
                    isSearchFieldFocused = false
                }
                withAnimation(PocketLedgerMotion.quick(reduceMotion: reduceMotion)) {
                    selectedTabRawValue = tab.rawValue
                }
            }
        )
    }

    private func handleDeepLink(_ url: URL) {
        guard let tab = AppTab(url: url) else { return }
        selectedTabBinding.wrappedValue = tab
    }

    private func openPendingIntentSearch() {
        guard let request = intentSearchRouter.consumePendingSearch() else { return }
        searchText = request.query
        selectedTabBinding.wrappedValue = .search
        isSearchPresented = true
        isSearchFieldFocused = true
    }

    private var unlockedContent: some View {
        TabView(selection: selectedTabBinding) {
            Tab(
                "Home",
                systemImage: AppTab.overview.systemImage,
                value: AppTab.overview
            ) {
                DashboardView(
                    store: store,
                    onAddExpense: { addAction = .expense },
                    onShowTransactions: { selectedTabBinding.wrappedValue = .transactions },
                    onAddAction: { addAction = $0 }
                )
            }
            .accessibilityIdentifier("tab-overview")

            Tab(value: AppTab.search, role: .search) {
                NavigationStack {
                    GlobalSearchView(store: store, searchText: $searchText)
                        .searchable(
                            text: $searchText,
                            isPresented: $isSearchPresented,
                            placement: .toolbar,
                            prompt: "Search accounts, transactions, descriptions…"
                        )
                        .searchFocused($isSearchFieldFocused)
                }
            }
            .accessibilityIdentifier("tab-search")

            Tab(
                "Transactions",
                systemImage: AppTab.transactions.systemImage,
                value: AppTab.transactions
            ) {
                NavigationStack {
                    TransactionsView(
                        store: store,
                        onAddExpense: { addAction = .expense },
                        onAddAction: { addAction = $0 }
                    )
                }
            }
            .accessibilityIdentifier("tab-transactions")

            Tab(
                "Accounts",
                systemImage: AppTab.accounts.systemImage,
                value: AppTab.accounts
            ) {
                NavigationStack {
                    AccountsView(store: store)
                }
            }
            .accessibilityIdentifier("tab-accounts")

            Tab(
                "More",
                systemImage: AppTab.more.systemImage,
                value: AppTab.more
            ) {
                MoreView(
                    store: store,
                    security: security,
                    onAddExpense: { addAction = .expense }
                )
            }
            .accessibilityIdentifier("tab-more")
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: selectedTabRawValue) { _, rawValue in
            guard rawValue == AppTab.search.rawValue else { return }
            isSearchPresented = true
            isSearchFieldFocused = true
        }
        .onChange(of: isSearchPresented) { _, isPresented in
            guard !isPresented, selectedTabBinding.wrappedValue == .search else { return }
            selectedTabBinding.wrappedValue = tabBeforeSearch
        }
        .tint(PocketLedgerTheme.accent)
        .preferredColorScheme(
            PocketLedgerAppearanceMode(rawValue: selectedAppearanceMode)?.preferredColorScheme
        )
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
            case .template(let templateID):
                if let template = store.data.templates.first(where: { $0.id == templateID }) {
                    TransactionEditor(store: store, template: template)
                } else {
                    EmptyView()
                }
            case .recent(let transactionID):
                if let transaction = store.data.transactions.first(where: { $0.id == transactionID }) {
                    TransactionEditor(store: store, prefilledTransaction: transaction)
                } else {
                    EmptyView()
                }
            }
        }
    }

    private var importWizardUITestDocument: ImportedDocument {
        ImportedDocument(
            fileName: "import-wizard-ui-test.csv",
            format: .delimited,
            tables: [
                ImportedTable(
                    id: "ui-test-rows",
                    name: "Imported rows",
                    columns: ["Date", "Amount", "Account", "Account Type", "Category", "Note"],
                    rows: [
                        ["2026-09-01", "10", "Gold", "Good", "Food", "Gold purchase"],
                        ["2026-09-02", "20", "Silver", "Silver", "Food", "Silver purchase"]
                    ]
                )
            ]
        )
    }

}

enum AddAction: Identifiable {
    case scanBill
    case expense
    case income
    case transfer
    case scheduled
    case template(UUID)
    case recent(UUID)

    var id: String {
        switch self {
        case .scanBill:
            return "scanBill"
        case .expense:
            return "expense"
        case .income:
            return "income"
        case .transfer:
            return "transfer"
        case .scheduled:
            return "scheduled"
        case .template(let id):
            return "template-\(id.uuidString)"
        case .recent(let id):
            return "recent-\(id.uuidString)"
        }
    }
}

@MainActor
private struct AddTransactionToolbar: ToolbarContent {
    @ObservedObject var store: LedgerStore
    let onAction: (AddAction) -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Section("Quick add") {
                    Button("Expense", systemImage: "arrow.up.right") { onAction(.expense) }
                    Button("Income", systemImage: "arrow.down.left") { onAction(.income) }
                    Button("Transfer", systemImage: "arrow.left.arrow.right") { onAction(.transfer) }
                }

                Section("Other") {
                    Button("Scan bill", systemImage: "doc.text.viewfinder") { onAction(.scanBill) }
                    Button("Scheduled", systemImage: "calendar.badge.clock") { onAction(.scheduled) }
                }

                if !store.data.templates.isEmpty {
                    Section("Templates") {
                        ForEach(Array(store.data.templates.prefix(3)), id: \.id) { template in
                            Button(template.name, systemImage: "rectangle.stack") {
                                onAction(.template(template.id))
                            }
                        }
                    }
                }

                if !store.recentTransactions.isEmpty {
                    Section("Recent") {
                        ForEach(Array(store.recentTransactions.prefix(3)), id: \.id) { transaction in
                            Button(transaction.note, systemImage: "clock.arrow.circlepath") {
                                onAction(.recent(transaction.id))
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add")
            .accessibilityHint("Choose what to add")
            .accessibilityIdentifier("add-transaction-button")
        }
    }
}

enum AppTab: String, Hashable {
    case overview
    case search
    case accounts
    case transactions
    case metrics
    case more

    static let tabBarOrder: [AppTab] = [.overview, .transactions, .accounts, .more, .search]

    var title: String {
        switch self {
        case .overview:
            return "Home"
        case .search:
            return "Search"
        case .accounts:
            return "Accounts"
        case .transactions:
            return "Transactions"
        case .metrics:
            return "Metrics"
        case .more:
            return "More"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "house.fill"
        case .search:
            return "magnifyingglass"
        case .accounts:
            return "wallet.pass"
        case .transactions:
            return "list.bullet.rectangle"
        case .metrics:
            return "chart.xyaxis.line"
        case .more:
            return "ellipsis.circle"
        }
    }

    init?(url: URL) {
        guard url.scheme == "pocketledger" else { return nil }
        let destination = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard destination == Self.overview.rawValue
            || destination == Self.accounts.rawValue
            || destination == Self.transactions.rawValue else {
            return nil
        }
        self.init(rawValue: destination)
    }
}

@MainActor
private struct MoreView: View {
    @ObservedObject var store: LedgerStore
    @ObservedObject var security: AppSecurityService
    let onAddExpense: () -> Void
    @State private var isShowingSetup = false
    @AppStorage(PocketLedgerTheme.colorThemeKey) private var selectedColorTheme = PocketLedgerColorTheme.ocean.rawValue
    @AppStorage(PocketLedgerTheme.appearanceModeKey) private var selectedAppearanceMode = PocketLedgerAppearanceMode.system.rawValue

    var body: some View {
        NavigationStack {
            List {
                if !store.attentionItems.isEmpty || !store.data.attentionState.dismissedIDs.isEmpty {
                    Section("Review") {
                        NavigationLink {
                            AttentionInboxView(store: store, onAddExpense: onAddExpense)
                        } label: {
                            Label {
                                HStack {
                                    Text("Needs attention")
                                    Spacer()
                                    Text("\(store.attentionItems.count)")
                                        .font(.caption.weight(.bold).monospacedDigit())
                                        .foregroundStyle(PocketLedgerTheme.warning)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(PocketLedgerTheme.warning)
                            }
                        }
                        .accessibilityHint("Review unresolved ledger items")
                    }
                }

                Section("Insights") {
                    NavigationLink {
                        MetricsView(store: store)
                    } label: {
                        Label("Metrics", systemImage: "chart.xyaxis.line")
                    }
                }

                Section("Planning") {
                    NavigationLink {
                        BudgetsView(store: store)
                    } label: {
                        Label("Budgets", systemImage: "chart.bar.doc.horizontal")
                    }

                    NavigationLink {
                        ScheduledTransactionsView(store: store)
                    } label: {
                        Label("Scheduled", systemImage: "calendar.badge.clock")
                    }

                    NavigationLink {
                        TemplatesView(store: store)
                    } label: {
                        Label("Templates", systemImage: "rectangle.stack")
                    }
                }

                Section("Organization") {
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
                }

                Section {
                    NavigationLink {
                        DataTransferView(store: store)
                    } label: {
                        Label("Import & Backup", systemImage: "externaldrive.badge.icloud")
                    }

                    NavigationLink {
                        SecuritySettingsView(store: store, security: security)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }

                    Button {
                        isShowingSetup = true
                    } label: {
                        Label("Setup guide", systemImage: "wand.and.stars")
                    }
                } header: {
                    Text("Data & security")
                } footer: {
                    Text("Keep advanced tools close without crowding the daily flow")
                }
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listRowBackground(PocketLedgerTheme.surface)
            .foregroundStyle(PocketLedgerTheme.textPrimary)
            .tint(PocketLedgerTheme.accent)
            .pocketScreen()
            .preferredColorScheme(
                PocketLedgerAppearanceMode(rawValue: selectedAppearanceMode)?.preferredColorScheme
            )
            .accessibilityIdentifier("more-screen-\(selectedColorTheme)")
            .sheet(isPresented: $isShowingSetup) {
                SetupWizardView(store: store)
            }
        }
    }
}

private enum DashboardSheet: Identifiable {
    case customization
    case transaction(LedgerTransaction)

    var id: String {
        switch self {
        case .customization:
            return "customization"
        case .transaction(let transaction):
            return "transaction-\(transaction.id.uuidString)"
        }
    }
}

@MainActor
private struct DashboardView: View {
    @ObservedObject var store: LedgerStore
    let onAddExpense: () -> Void
    let onShowTransactions: () -> Void
    let onAddAction: (AddAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentedSheet: DashboardSheet?
    @State private var snapshot = DashboardSnapshot.empty
    @State private var dashboardPreferences = DashboardPreferences.load()
    @AppStorage(PocketLedgerTheme.colorThemeKey) private var selectedColorTheme = PocketLedgerColorTheme.ocean.rawValue
    @AppStorage(PocketLedgerTheme.appearanceModeKey) private var selectedAppearanceMode = PocketLedgerAppearanceMode.system.rawValue

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                PocketGlassContainer(spacing: 14) {
                    VStack(alignment: .leading, spacing: 16) {
                        dashboardDateHeader
                        if !store.storageAvailable || !store.sharedStorageAvailable {
                            storageNotice
                        }
                        dashboardWidgets

                        if let status = store.lastActionStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(PocketLedgerTheme.textTertiary)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, PocketLedgerTheme.screenHorizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .pocketScreen()
            .accessibilityIdentifier("dashboard-\(selectedColorTheme)")
            .preferredColorScheme(
                PocketLedgerAppearanceMode(rawValue: selectedAppearanceMode)?.preferredColorScheme
            )
            .navigationTitle("Pocket Ledger")
            .navigationBarTitleDisplayMode(.large)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        presentedSheet = .customization
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Customize dashboard")
                    .accessibilityHint("Choose which widgets appear and reorder them")
                    .accessibilityIdentifier("dashboard-customize")
                }
                AddTransactionToolbar(store: store, onAction: onAddAction)
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .customization:
                    DashboardCustomizationView(preferences: $dashboardPreferences)
                case .transaction(let transaction):
                    TransactionEditor(store: store, transaction: transaction)
                }
            }
            .onAppear(perform: refreshSnapshot)
            .onChange(of: store.ledgerRevision) { _, _ in
                withAnimation(PocketLedgerMotion.expressive(reduceMotion: reduceMotion)) {
                    refreshSnapshot()
                }
            }
            .onChange(of: dashboardPreferences) { _, preferences in preferences.save() }
        }
    }

    private var dashboardDateHeader: some View {
        Text(Date.now, style: .date)
            .font(.subheadline)
            .foregroundStyle(PocketLedgerTheme.textSecondary)
    }

    @ViewBuilder
    private var dashboardWidgets: some View {
        if dashboardPreferences.enabledWidgets.isEmpty {
            dashboardEmptyState
        } else {
            ForEach(dashboardPreferences.enabledWidgets) { widget in
                dashboardWidget(widget)
            }
        }
    }

    @ViewBuilder
    private func dashboardWidget(_ widget: DashboardWidget) -> some View {
        switch widget {
        case .balance:
            balanceHero
        case .attention:
            attentionSnapshot
        case .accounts:
            accountBreakdown
        case .monthSummary:
            monthSnapshot
        case .recentActivity:
            recentActivity
        case .upcoming:
            upcomingSchedules
        case .cashFlow:
            cashFlowSnapshot
        case .budgetPulse:
            budgetSnapshot
        case .storageStatus:
            if store.storageAvailable && store.sharedStorageAvailable {
                storageNotice
            }
        }
    }

    private var dashboardEmptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Your dashboard is empty", systemImage: "rectangle.stack.badge.plus")
                .font(.headline)
            Text("Choose the widgets you want to see here, then drag them into your preferred order.")
                .font(.subheadline)
                .foregroundStyle(PocketLedgerTheme.textSecondary)
            Button("Choose widgets", systemImage: "slider.horizontal.3") {
                presentedSheet = .customization
            }
            .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .pocketGroupedSurface(cornerRadius: 20)
    }

    private var balanceHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Available balance", systemImage: "wallet.pass.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PocketLedgerTheme.textSecondary)

                Spacer()

                Text("SEPARATE CURRENCIES")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(PocketLedgerTheme.textTertiary)
            }

            VStack(spacing: 0) {
                ForEach(LedgerCurrency.allCases) { currency in
                    if currency != LedgerCurrency.allCases[0] {
                        Divider()
                            .overlay(PocketLedgerTheme.divider)
                    }
                    balanceRow(for: currency)
                }
            }

            Text("Loans are tracked separately in Accounts.")
                .font(.caption)
                .foregroundStyle(PocketLedgerTheme.textTertiary)
        }
        .padding(20)
        .pocketGroupedSurface(cornerRadius: 22)
    }

    private func balanceRow(for currency: LedgerCurrency) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(currency.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(currency == .usd ? PocketLedgerTheme.income : PocketLedgerTheme.textSecondary)
                Text(currency.displayName)
                    .font(.caption2)
                    .foregroundStyle(PocketLedgerTheme.textTertiary)
            }

            Spacer(minLength: 12)

            let balance = snapshot.availableBalances[currency] ?? Money(currency: currency, minorUnits: 0)
            Text(balance.formatted)
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .multilineTextAlignment(.trailing)
                .contentTransition(.numericText(value: Double(balance.minorUnits)))
                .animation(
                    PocketLedgerMotion.expressive(reduceMotion: reduceMotion),
                    value: balance.minorUnits
                )
        }
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var attentionSnapshot: some View {
        if !snapshot.attentionItems.isEmpty {
            NavigationLink {
                AttentionInboxView(store: store, onAddExpense: onAddExpense)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(PocketLedgerTheme.warning)
                        .frame(width: 38, height: 38)
                        .pocketGlassSurface(cornerRadius: 19, tint: PocketLedgerTheme.warning.opacity(0.14))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Needs attention")
                            .font(.headline)
                            .foregroundStyle(PocketLedgerTheme.textPrimary)
                        Text("\(snapshot.attentionItems.count) area\(snapshot.attentionItems.count == 1 ? "" : "s") to review")
                            .font(.subheadline)
                            .foregroundStyle(PocketLedgerTheme.textSecondary)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PocketLedgerTheme.textTertiary)
                }
                .padding(16)
                .pocketGroupedSurface(cornerRadius: 20)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(PocketLedgerTheme.warning.opacity(0.28), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Needs attention, \(snapshot.attentionItems.count) areas to review")
            .accessibilityIdentifier("dashboard-needs-attention")
        }
    }

    private var accountBreakdown: some View {
        let activeAccounts = snapshot.activeAccounts
        let includedCount = snapshot.includedAccountCount
        let excludedCount = snapshot.excludedAccountCount

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Balance scope")
                        .font(.title3.weight(.bold))
                    Text("Account balances by type")
                        .font(.caption)
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                }
                Spacer()
                NavigationLink {
                    AccountsView(store: store)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PocketLedgerTheme.textTertiary)
                }
                .accessibilityLabel("Open accounts")
            }

            HStack(spacing: 10) {
                scopeMetric(title: "Included", value: "\(includedCount)", tint: PocketLedgerTheme.positive)
                scopeMetric(title: "Excluded", value: "\(excludedCount)", tint: PocketLedgerTheme.textTertiary)
            }

            Text(excludedCount == 0
                 ? "Included accounts feed totals; loans remain separate from available balance."
                 : "Excluded accounts remain visible in Accounts but do not affect balances or metrics. Loans remain separate from available balance.")
                .font(.caption)
                .foregroundStyle(PocketLedgerTheme.textSecondary)

            if activeAccounts.isEmpty {
                Text("Add an account to start tracking a balance.")
                    .font(.subheadline)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
            } else {
                ForEach(AccountType.allCases) { type in
                    let accounts = activeAccounts.filter { $0.type == type }
                    if !accounts.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Label(type.displayName, systemImage: type.systemImage)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(PocketLedgerTheme.textSecondary)

                            ForEach(accounts.prefix(3)) { account in
                                HStack(spacing: 9) {
                                    Circle()
                                        .fill(account.includeInTotals ? PocketLedgerTheme.accent : PocketLedgerTheme.textTertiary)
                                        .frame(width: 7, height: 7)
                                    Text(account.name)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(store.ledgerIndex.balance(for: account).formatted)
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(account.includeInTotals ? PocketLedgerTheme.textPrimary : PocketLedgerTheme.textTertiary)
                                }
                            }
                            if accounts.count > 3 {
                                Text("+\(accounts.count - 3) more")
                                    .font(.caption)
                                    .foregroundStyle(PocketLedgerTheme.textTertiary)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .pocketGroupedSurface(cornerRadius: 20)
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(PocketLedgerTheme.divider, lineWidth: 1)
        }
    }

    private func scopeMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(PocketLedgerTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .pocketGlassSurface(cornerRadius: 15)
    }

    private var monthSnapshot: some View {
        let expenses = snapshot.monthExpenses

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "This month", detail: Date.now.formatted(.dateTime.month(.wide).year()))

            HStack(spacing: 10) {
                NavigationLink {
                    TransactionsView(
                        store: store,
                        onAddExpense: onAddExpense,
                        initialFilter: .all,
                        initialPeriod: .thisMonth
                    )
                } label: {
                    snapshotMetric(
                        title: "Transactions",
                        value: "\(snapshot.monthTransactionCount)",
                        systemImage: "arrow.left.arrow.right",
                        tint: PocketLedgerTheme.income
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TransactionsView(
                        store: store,
                        onAddExpense: onAddExpense,
                        initialFilter: .expense,
                        initialPeriod: .thisMonth,
                        initialSearch: snapshot.topCategory ?? ""
                    )
                } label: {
                    snapshotMetric(
                        title: "Top category",
                        value: snapshot.topCategory ?? "No activity",
                        systemImage: "tag.fill",
                        tint: PocketLedgerTheme.accent
                    )
                }
                .buttonStyle(.plain)
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
            .pocketGroupedSurface(cornerRadius: 17)
        }
    }

    @ViewBuilder
    private var upcomingSchedules: some View {
        let schedules = snapshot.upcomingSchedules

        if !schedules.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionHeader(title: "Upcoming", detail: "Bills & recurring entries")
                    NavigationLink {
                        ScheduledTransactionsView(store: store)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PocketLedgerTheme.textTertiary)
                    }
                    .accessibilityLabel("Open scheduled transactions")
                }

                VStack(spacing: 0) {
                    ForEach(Array(schedules.prefix(3))) { schedule in
                        upcomingScheduleRow(schedule)
                        if schedule.id != schedules.prefix(3).last?.id {
                            Divider().overlay(PocketLedgerTheme.divider)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .pocketGroupedSurface(cornerRadius: 17)

                if schedules.count > 3 {
                    Text("+\(schedules.count - 3) more scheduled \(schedules.count - 3 == 1 ? "entry" : "entries")")
                        .font(.caption)
                        .foregroundStyle(PocketLedgerTheme.textTertiary)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    private func upcomingScheduleRow(_ schedule: ScheduledTransaction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: schedule.kind == .income ? "arrow.down.left" : "calendar.badge.clock")
                .font(.body.weight(.semibold))
                .foregroundStyle(schedule.kind == .income ? PocketLedgerTheme.income : PocketLedgerTheme.accent)
                .frame(width: 28, height: 28)
                .pocketGlassSurface(cornerRadius: 14, tint: PocketLedgerTheme.accent.opacity(0.14))

            VStack(alignment: .leading, spacing: 3) {
                Text(schedule.note.isEmpty ? schedule.kind.displayName : schedule.note)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(store.transactionSummary(schedule.transactionTemplate))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(upcomingDateLabel(schedule.nextRunDate))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PocketLedgerTheme.accent)
                Text(schedule.nextRunDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(PocketLedgerTheme.textTertiary)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(schedule.note.isEmpty ? schedule.kind.displayName : schedule.note), \(store.transactionSummary(schedule.transactionTemplate)), \(schedule.nextRunDate.formatted(date: .abbreviated, time: .shortened))"
        )
    }

    private func upcomingDateLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0

        switch days {
        case ..<0:
            return "Due"
        case 0:
            return "Today"
        case 1:
            return "Tomorrow"
        case 2...6:
            return "In \(days) days"
        default:
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
    }

    @ViewBuilder
    private var cashFlowSnapshot: some View {
        let schedules = snapshot.cashFlowSchedules

        if !schedules.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionHeader(title: "Next 30 days", detail: "Projected cash flow")
                    NavigationLink {
                        ScheduledTransactionsView(store: store)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PocketLedgerTheme.textTertiary)
                    }
                    .accessibilityLabel("Open cash flow schedules")
                }

                Text("Confirmed balances plus enabled recurring entries. Scheduled items are not included in the ledger until they run.")
                    .font(.caption)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)

                VStack(spacing: 0) {
                    ForEach(LedgerCurrency.allCases) { currency in
                        let current = snapshot.availableBalances[currency]
                            ?? Money(currency: currency, minorUnits: 0)
                        let change = snapshot.scheduledChanges[currency] ?? 0
                        let projected = Money(currency: currency, minorUnits: current.minorUnits + change)

                        if currency != LedgerCurrency.allCases[0] {
                            Divider().overlay(PocketLedgerTheme.divider)
                        }

                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(currency.rawValue)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                                Text("\(schedules.count) scheduled \(schedules.count == 1 ? "entry" : "entries")")
                                    .font(.caption2)
                                    .foregroundStyle(PocketLedgerTheme.textTertiary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 3) {
                                Text(projected.formatted)
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(projected.minorUnits < 0 ? PocketLedgerTheme.warning : PocketLedgerTheme.textPrimary)
                                Text(change >= 0 ? "+\(Money(currency: currency, minorUnits: change).formatted) scheduled"
                                     : "\(Money(currency: currency, minorUnits: change).formatted) scheduled")
                                    .font(.caption2.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(change >= 0 ? PocketLedgerTheme.income : PocketLedgerTheme.warning)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 14)
                .pocketGroupedSurface(cornerRadius: 17)

                if LedgerCurrency.allCases.contains(where: {
                    (snapshot.scheduledChanges[$0] ?? 0) < 0
                }) {
                    Label("Review upcoming outflows before they affect your available balance.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(PocketLedgerTheme.warning)
                }
            }
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
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(PocketLedgerTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(13)
        .pocketGroupedSurface(cornerRadius: 17)
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
            HStack(alignment: .firstTextBaseline) {
                Text("Recent activity")
                    .font(.title3.weight(.bold))
                Spacer()
                Button("See all", action: onShowTransactions)
                    .buttonStyle(.plain)
                    .foregroundStyle(PocketLedgerTheme.accent)
                    .accessibilityLabel("See all transactions")
                    .accessibilityHint("Opens transaction history")
                    .font(.caption.weight(.semibold))
            }

            if snapshot.recentTransactions.isEmpty {
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
                    Button("Add expense", systemImage: "plus", action: onAddExpense)
                        .buttonStyle(.glassProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .pocketCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(snapshot.recentTransactions.prefix(5))) { transaction in
                        TransactionRow(
                            transaction: transaction,
                            store: store,
                            onEdit: { presentedSheet = .transaction(transaction) },
                            onDuplicate: {},
                            onDelete: {},
                            onSaveTemplate: {},
                            allowsActions: false
                        )
                        .transition(
                            reduceMotion
                                ? .identity
                                : .move(edge: .top).combined(with: .opacity)
                        )
                        Divider().overlay(PocketLedgerTheme.divider)
                    }
                }
                .padding(.horizontal, 14)
                .pocketGroupedSurface(cornerRadius: 18)
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(PocketLedgerTheme.divider, lineWidth: 1)
                }
            }
        }
    }

    @ViewBuilder
    private var budgetSnapshot: some View {
        if !snapshot.budgetSummaries.isEmpty {
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
                    ForEach(Array(snapshot.budgetSummaries.prefix(3))) { summary in
                        let budget = summary.budget
                        let spent = summary.spent
                        let allowance = summary.allowance
                        let over = summary.isOver
                        let remaining = summary.remaining
                        let projectedOver = summary.isProjectedOver
                        let ratio = summary.ratio

                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(summary.categoryPath)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(spent.formatted) / \(allowance.formatted)")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(over ? PocketLedgerTheme.warning : PocketLedgerTheme.textSecondary)
                            }
                            ProgressView(value: ratio)
                                .tint(projectedOver ? PocketLedgerTheme.warning : PocketLedgerTheme.accent)
                            HStack(spacing: 10) {
                                Text(over
                                     ? "Over by \(Money(currency: budget.currency, minorUnits: -remaining).formatted)"
                                     : "Remaining \(Money(currency: budget.currency, minorUnits: remaining).formatted)")
                                    .foregroundStyle(over ? PocketLedgerTheme.warning : PocketLedgerTheme.positive)
                                Spacer()
                                Text("Projected \(summary.projected.formatted)")
                                    .foregroundStyle(projectedOver ? PocketLedgerTheme.warning : PocketLedgerTheme.textTertiary)
                            }
                            .font(.caption.weight(.semibold).monospacedDigit())
                        }
                    }
                }
                .padding(14)
                .pocketGroupedSurface(cornerRadius: 17)
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
        .pocketGlassCapsule(tint: PocketLedgerTheme.accent.opacity(0.08))
    }

    private func refreshSnapshot() {
        snapshot = DashboardSnapshot.make(
            data: store.data,
            index: store.ledgerIndex,
            attentionItems: store.attentionItems
        )
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

@MainActor
private struct DashboardCustomizationView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var preferences: DashboardPreferences

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Turn widgets on or off. Tap Edit to drag them into your preferred order.")
                        .font(.subheadline)
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                        .listRowBackground(PocketLedgerTheme.surface)
                }

                Section("Dashboard widgets") {
                    ForEach(preferences.order) { widget in
                        Toggle(isOn: Binding(
                            get: { !preferences.disabledWidgets.contains(widget) },
                            set: { preferences.setEnabled($0, for: widget) }
                        )) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(widget.title)
                                    Text(widget.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                                }
                            } icon: {
                                Image(systemName: widget.systemImage)
                                    .foregroundStyle(PocketLedgerTheme.accent)
                            }
                        }
                        .accessibilityIdentifier("dashboard-widget-\(widget.rawValue)")
                        .listRowBackground(PocketLedgerTheme.surface)
                    }
                    .onMove { source, destination in
                        preferences.move(from: source, to: destination)
                    }
                }

                Section {
                    Button("Reset dashboard", role: .destructive) {
                        preferences.reset()
                    }
                } footer: {
                    Text("Reset restores the default widgets and order.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            .background(PocketLedgerTheme.background)
            .navigationTitle("Customize dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            }
            .tint(PocketLedgerTheme.accent)
            .foregroundStyle(PocketLedgerTheme.textPrimary)
        }
    }
}

@MainActor
private struct AttentionInboxView: View {
    @ObservedObject var store: LedgerStore
    let onAddExpense: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if store.attentionItems.isEmpty {
                    emptyState
                } else {
                    Text("Resolve these items to keep balances, budgets, and metrics trustworthy.")
                        .font(.subheadline)
                        .foregroundStyle(PocketLedgerTheme.textSecondary)

                    ForEach(store.attentionItems) { item in
                        attentionCard(item)
                    }
                }

                if !store.data.attentionState.dismissedIDs.isEmpty {
                    Button("Restore dismissed items", systemImage: "arrow.uturn.backward") {
                        _ = store.restoreDismissedAttention()
                    }
                    .buttonStyle(.glass)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .pocketScreen()
        .navigationTitle("Needs attention")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("needs-attention-inbox")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(PocketLedgerTheme.positive)
            Text("Everything looks clear")
                .font(.headline)
            Text("Pocket Ledger has no unresolved balance, budget, or transaction issues.")
                .font(.subheadline)
                .foregroundStyle(PocketLedgerTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
        .padding(.horizontal, 20)
        .pocketGroupedSurface(cornerRadius: 20)
    }

    private func attentionCard(_ item: FinanceAttentionItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(item.severity == .warning ? PocketLedgerTheme.warning : PocketLedgerTheme.accent)
                .frame(width: 38, height: 38)
                .pocketGlassSurface(
                    cornerRadius: 19,
                    tint: (item.severity == .warning ? PocketLedgerTheme.warning : PocketLedgerTheme.accent).opacity(0.14)
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.headline)
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                Text("\(item.count) \(item.count == 1 ? "item" : "items")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PocketLedgerTheme.textTertiary)

                NavigationLink {
                    destination(for: item.destination)
                } label: {
                    Label("Review", systemImage: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glassProminent)
                .tint(item.severity == .warning ? PocketLedgerTheme.warning : PocketLedgerTheme.accent)
                .padding(.top, 3)
            }

            Spacer(minLength: 0)

            Button {
                _ = store.dismissAttention(id: item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Dismiss \(item.title)")
        }
        .padding(16)
        .pocketGroupedSurface(cornerRadius: 20)
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(PocketLedgerTheme.divider, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func destination(for destination: FinanceAttentionDestination) -> some View {
        switch destination {
        case .uncategorizedTransactions:
            TransactionsView(
                store: store,
                onAddExpense: onAddExpense,
                initialFilter: .uncategorized
            )
        case .transferTransactions:
            TransactionsView(
                store: store,
                onAddExpense: onAddExpense,
                initialFilter: .transfer
            )
        case .scheduledTransactions:
            ScheduledTransactionsView(store: store)
        case .budgets:
            BudgetsView(store: store)
        }
    }
}

enum TransactionFilter: String, CaseIterable, Identifiable, Hashable {
    case all = "All"
    case expense = "Expenses"
    case income = "Income"
    case transfer = "Transfers"
    case uncategorized = "Uncategorized"

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
        case .uncategorized:
            return .expense
        }
    }
}

enum TransactionPeriod: String, CaseIterable, Identifiable, Hashable {
    case all = "All time"
    case thisMonth = "This month"
    case lastMonth = "Last month"
    case thisYear = "This year"
    case custom = "Custom range"

    var id: String { rawValue }

    func includes(_ date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: .now)?.contains(date) ?? true
        case .lastMonth:
            guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: .now) else {
                return true
            }
            return calendar.dateInterval(of: .month, for: lastMonth)?.contains(date) ?? true
        case .thisYear:
            return calendar.dateInterval(of: .year, for: .now)?.contains(date) ?? true
        case .custom:
            return true
        }
    }
}

private enum TransactionQuickFilter: String, CaseIterable, Identifiable {
    case none
    case thisMonth
    case uncategorized
    case needsReceipt
    case cash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "All transactions"
        case .thisMonth:
            return "This month"
        case .uncategorized:
            return "Uncategorized"
        case .needsReceipt:
            return "Needs receipt"
        case .cash:
            return "Cash"
        }
    }
}

private struct TransactionDay: Identifiable {
    let date: Date
    let transactions: [LedgerTransaction]

    var id: Date { date }
}

private struct TransactionListSnapshot {
    let filteredTransactions: [LedgerTransaction]
    let pageTransactions: [LedgerTransaction]
    let groupedTransactions: [TransactionDay]
    let pageCount: Int
    let displayedPage: Int
    let expenseTotals: [LedgerCurrency: Int64]

    static var empty: TransactionListSnapshot {
        TransactionListSnapshot(
            filteredTransactions: [],
            pageTransactions: [],
            groupedTransactions: [],
            pageCount: 1,
            displayedPage: 0,
            expenseTotals: [:]
        )
    }

    static func make(
        index: LedgerIndex,
        filter: TransactionFilter,
        period: TransactionPeriod,
        quickFilter: TransactionQuickFilter,
        searchText: String,
        customStartDate: Date,
        customEndDate: Date,
        page: Int,
        pageSize: Int,
        calendar: Calendar = .current
    ) -> TransactionListSnapshot {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredTransactions = index.sortedTransactions.filter { transaction in
            let matchesKind: Bool
            if filter == .uncategorized {
                matchesKind = transaction.kind == .expense && transaction.categoryID == nil
            } else {
                matchesKind = filter.kind.map { transaction.kind == $0 } ?? true
            }
            guard matchesKind else { return false }

            let matchesPeriod: Bool
            if period == .custom {
                let start = calendar.startOfDay(for: customStartDate)
                let end = calendar.date(
                    byAdding: DateComponents(day: 1),
                    to: calendar.startOfDay(for: customEndDate)
                ) ?? customEndDate
                matchesPeriod = transaction.date >= start && transaction.date < end
            } else {
                matchesPeriod = period.includes(transaction.date, calendar: calendar)
            }
            guard matchesPeriod else { return false }

            switch quickFilter {
            case .none, .thisMonth, .uncategorized:
                break
            case .needsReceipt:
                guard transaction.attachmentIDs.isEmpty else { return false }
            case .cash:
                guard (transaction.outflows + transaction.inflows).contains(where: {
                    index.account(with: $0.accountID)?.type == .cash
                }) else { return false }
            }

            guard !query.isEmpty else { return true }
            return FinanceSearch.matches(transaction, query: query, index: index)
        }

        let pageCount = max(1, (filteredTransactions.count + pageSize - 1) / pageSize)
        let displayedPage = min(page, pageCount - 1)
        let pageStart = displayedPage * pageSize
        let pageTransactions = Array(
            filteredTransactions.dropFirst(pageStart).prefix(pageSize)
        )
        let grouped = Dictionary(grouping: pageTransactions) {
            calendar.startOfDay(for: $0.date)
        }
        let groupedTransactions = grouped.keys.sorted(by: >).map { date in
            TransactionDay(date: date, transactions: grouped[date] ?? [])
        }

        var expenseTotals: [LedgerCurrency: Int64] = [:]
        for transaction in filteredTransactions where transaction.kind == .expense {
            for currency in LedgerCurrency.allCases {
                expenseTotals[currency, default: 0] += index.netExpenseAmount(
                    transaction,
                    currency: currency
                )
            }
        }

        return TransactionListSnapshot(
            filteredTransactions: filteredTransactions,
            pageTransactions: pageTransactions,
            groupedTransactions: groupedTransactions,
            pageCount: pageCount,
            displayedPage: displayedPage,
            expenseTotals: expenseTotals
        )
    }
}

@MainActor
struct TransactionsView: View {
    private static let lastQuickFilterKey = "pocketLedger.lastTransactionQuickFilter"

    @ObservedObject var store: LedgerStore
    let onAddExpense: () -> Void
    private let onAddAction: ((AddAction) -> Void)?
    @State private var selectedFilter: TransactionFilter
    @State private var selectedPeriod: TransactionPeriod
    @State private var selectedQuickFilter: TransactionQuickFilter
    private let searchText: String
    @State private var customStartDate: Date
    @State private var customEndDate: Date
    @State private var transactionPage = 0
    @State private var editingTransaction: LedgerTransaction?
    @State private var transactionToTemplate: LedgerTransaction?
    @State private var isPresentingBillScanner = false
    @State private var isShowingFilters = false
    @State private var isSelectingTransactions = false
    @State private var selectedTransactionIDs: Set<UUID> = []
    @State private var isShowingBulkDeleteConfirmation = false
    @State private var deletedTransactionsForUndo: [LedgerTransaction] = []
    @State private var listSnapshot = TransactionListSnapshot.empty

    private let transactionsPerPage = 25

    init(
        store: LedgerStore,
        onAddExpense: @escaping () -> Void = {},
        onAddAction: ((AddAction) -> Void)? = nil,
        initialFilter: TransactionFilter = .all,
        initialPeriod: TransactionPeriod = .all,
        initialSearch: String = ""
    ) {
        _store = ObservedObject(wrappedValue: store)
        self.onAddExpense = onAddExpense
        self.onAddAction = onAddAction
        _selectedFilter = State(initialValue: initialFilter)
        _selectedPeriod = State(initialValue: initialPeriod)
        let hasExplicitContext = initialFilter != .all || initialPeriod != .all || !initialSearch.isEmpty
        let persistedQuickFilter = TransactionQuickFilter(
            rawValue: UserDefaults.standard.string(forKey: Self.lastQuickFilterKey) ?? ""
        ) ?? .none
        _selectedQuickFilter = State(
            initialValue: initialFilter == .uncategorized
                ? .uncategorized
                : hasExplicitContext ? .none : persistedQuickFilter
        )
        self.searchText = initialSearch
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -30, to: .now) ?? .now
        _customStartDate = State(initialValue: start)
        _customEndDate = State(initialValue: .now)
    }

    var body: some View {
        List {
            screenSubtitle
                .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 2, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if isSelectingTransactions {
                selectionToolbar
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            filtersButton
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            transactionsSummary
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if listSnapshot.filteredTransactions.isEmpty {
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
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Button("Add expense", systemImage: "plus", action: onAddExpense)
                    .buttonStyle(.glassProminent)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(listSnapshot.groupedTransactions) { day in
                    Section {
                        ForEach(day.transactions) { transaction in
                            transactionRow(for: transaction)
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(PocketLedgerTheme.surface)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .stroke(PocketLedgerTheme.divider, lineWidth: 1)
                                        }
                                )
                                .listRowSeparator(.hidden)
                        }
                    } header: {
                        dayHeader(day)
                    }
                    .textCase(nil)
                    .listSectionSeparator(.hidden)
                }

                transactionPagination
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 24, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .pocketScreen()
        .navigationTitle("Transactions")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isSelectingTransactions {
                    Button("Done") {
                        isSelectingTransactions = false
                        selectedTransactionIDs.removeAll()
                    }
                } else {
                    Button {
                        isSelectingTransactions = true
                    } label: {
                        Image(systemName: "checklist")
                    }
                    .accessibilityLabel("Select transactions")
                    .accessibilityIdentifier("select-transactions")
                }
            }
            if let onAddAction {
                AddTransactionToolbar(store: store, onAction: onAddAction)
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingBillScanner = true
                    } label: {
                        Image(systemName: "doc.viewfinder")
                    }
                    .accessibilityLabel("Scan bill")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !deletedTransactionsForUndo.isEmpty {
                undoBanner(for: deletedTransactionsForUndo)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .onAppear(perform: refreshListSnapshot)
        .onChange(of: selectedFilter) { _, _ in
            transactionPage = 0
            refreshListSnapshot()
        }
        .onChange(of: selectedPeriod) { _, _ in
            transactionPage = 0
            refreshListSnapshot()
        }
        .onChange(of: customStartDate) { _, _ in
            if customStartDate > customEndDate {
                customEndDate = customStartDate
            }
            transactionPage = 0
            refreshListSnapshot()
        }
        .onChange(of: customEndDate) { _, _ in
            if customEndDate < customStartDate {
                customStartDate = customEndDate
            }
            transactionPage = 0
            refreshListSnapshot()
        }
        .onChange(of: selectedQuickFilter) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.lastQuickFilterKey)
            transactionPage = 0
            refreshListSnapshot()
        }
        .onChange(of: transactionPage) { _, _ in refreshListSnapshot() }
        .onChange(of: store.ledgerRevision) { _, _ in
            transactionPage = 0
            refreshListSnapshot()
        }
        .sheet(isPresented: $isPresentingBillScanner) {
            BillScannerView(store: store)
        }
        .sheet(item: $editingTransaction) { transaction in
            TransactionEditor(store: store, transaction: transaction)
        }
        .sheet(item: $transactionToTemplate) { transaction in
            TemplateNameEditor(store: store, transaction: transaction)
        }
    }

    private var activeFilterSummary: String {
        let kind = selectedQuickFilter != .none && selectedQuickFilter != .thisMonth
            ? selectedQuickFilter.title
            : selectedFilter.rawValue
        let period = selectedPeriod == .custom
            ? "\(customStartDate.formatted(date: .abbreviated, time: .omitted))–\(customEndDate.formatted(date: .abbreviated, time: .omitted))"
            : selectedPeriod.rawValue
        return "\(kind) · \(period)"
    }

    private var filtersButton: some View {
        Button {
            isShowingFilters = true
        } label: {
            HStack(spacing: 10) {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(activeFilterSummary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PocketLedgerTheme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .pocketGlassSurface(cornerRadius: 13)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transaction-filters")
        .sheet(isPresented: $isShowingFilters) {
            NavigationStack {
                Form {
                    Section("Type") {
                        Picker("Transactions", selection: $selectedFilter) {
                            ForEach(TransactionFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Section("Date range") {
                        Picker("Period", selection: $selectedPeriod) {
                            ForEach(TransactionPeriod.allCases) { period in
                                Text(period.rawValue).tag(period)
                            }
                        }

                        if selectedPeriod == .custom {
                            DatePicker("From", selection: $customStartDate, displayedComponents: .date)
                            DatePicker("To", selection: $customEndDate, displayedComponents: .date)
                        }
                    }

                    Section("Saved filter") {
                        Menu {
                            ForEach(TransactionQuickFilter.allCases) { filter in
                                Button {
                                    applyQuickFilter(filter)
                                } label: {
                                    if selectedQuickFilter == filter {
                                        Label(filter.title, systemImage: "checkmark")
                                    } else {
                                        Text(filter.title)
                                    }
                                }
                            }
                        } label: {
                            Label("Saved filter: \(selectedQuickFilter.title)", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityIdentifier("transaction-saved-filter")
                    }
                }
                .navigationTitle("Filters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isShowingFilters = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func transactionRow(for transaction: LedgerTransaction) -> some View {
        TransactionRow(
            transaction: transaction,
            store: store,
            onEdit: {
                if isSelectingTransactions {
                    toggleSelection(for: transaction)
                } else {
                    editingTransaction = transaction
                }
            },
            onDuplicate: { _ = store.duplicateTransaction(id: transaction.id) },
            onDelete: {
                if store.deleteTransaction(id: transaction.id) {
                    deletedTransactionsForUndo = [transaction]
                }
            },
            onSaveTemplate: { transactionToTemplate = transaction },
            allowsActions: !isSelectingTransactions,
            isSelectionMode: isSelectingTransactions,
            isSelected: selectedTransactionIDs.contains(transaction.id),
            onToggleSelection: { toggleSelection(for: transaction) }
        )
    }

    private var selectionToolbar: some View {
        HStack(spacing: 10) {
            Text("\(selectedTransactionIDs.count) selected")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(PocketLedgerTheme.textSecondary)

            Spacer()

            Menu {
                Button("Remove category", systemImage: "tag.slash") {
                    applyBulkCategory(nil)
                }
                ForEach(store.activeCategories) { category in
                    Button(store.categoryPath(for: category.id), systemImage: category.systemImage) {
                        applyBulkCategory(category.id)
                    }
                }
            } label: {
                Label("Category", systemImage: "tag")
            }
            .disabled(selectedTransactionIDs.isEmpty)

            Menu {
                ForEach(store.activeAccounts) { account in
                    Button("\(account.name) · \(account.currency.rawValue)", systemImage: account.type.systemImage) {
                        applyBulkAccount(account.id)
                    }
                }
            } label: {
                Label("Account", systemImage: "wallet.pass")
            }
            .disabled(selectedTransactionIDs.isEmpty)

            Button {
                isShowingBulkDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glass)
            .tint(PocketLedgerTheme.warning)
            .disabled(selectedTransactionIDs.isEmpty)
            .accessibilityLabel("Delete selected transactions")
        }
        .padding(12)
        .pocketGlassSurface(cornerRadius: 16, tint: PocketLedgerTheme.accent.opacity(0.08))
        .confirmationDialog(
            "Delete selected transactions?",
            isPresented: $isShowingBulkDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(selectedTransactionIDs.count) transactions", role: .destructive) {
                let selected = store.data.transactions.filter {
                    selectedTransactionIDs.contains($0.id)
                }
                if store.deleteTransactions(ids: selectedTransactionIDs) {
                    deletedTransactionsForUndo = selected
                    selectedTransactionIDs.removeAll()
                    isSelectingTransactions = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can be undone from the message at the bottom of the screen.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transaction selection tools")
        .accessibilityIdentifier("transaction-selection-toolbar")
    }

    private func undoBanner(for transactions: [LedgerTransaction]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(PocketLedgerTheme.warning)
            Text(transactions.count == 1
                 ? "Deleted \(transactions[0].note.isEmpty ? "transaction" : transactions[0].note)"
                 : "Deleted \(transactions.count) transactions")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Undo") {
                _ = store.restoreTransactions(transactions)
                deletedTransactionsForUndo.removeAll()
            }
            .font(.subheadline.weight(.bold))
            Button {
                deletedTransactionsForUndo.removeAll()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Dismiss undo message")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 7)
        .pocketGlassCapsule(tint: PocketLedgerTheme.warning.opacity(0.12))
        .accessibilityElement(children: .contain)
    }

    private var screenSubtitle: some View {
        Text("Every inflow and outflow, in one place")
            .font(.subheadline)
            .foregroundStyle(PocketLedgerTheme.textSecondary)
    }

    private func toggleSelection(for transaction: LedgerTransaction) {
        if selectedTransactionIDs.contains(transaction.id) {
            selectedTransactionIDs.remove(transaction.id)
        } else {
            selectedTransactionIDs.insert(transaction.id)
        }
    }

    private func applyBulkCategory(_ categoryID: UUID?) {
        guard !selectedTransactionIDs.isEmpty else { return }
        if store.updateTransactionCategories(ids: selectedTransactionIDs, categoryID: categoryID) {
            selectedTransactionIDs.removeAll()
            isSelectingTransactions = false
        }
    }

    private func applyBulkAccount(_ accountID: UUID) {
        guard !selectedTransactionIDs.isEmpty else { return }
        if store.updateSingleAccountTransactions(ids: selectedTransactionIDs, accountID: accountID) {
            selectedTransactionIDs.removeAll()
            isSelectingTransactions = false
        }
    }

    private func applyQuickFilter(_ filter: TransactionQuickFilter) {
        selectedQuickFilter = filter
        switch filter {
        case .none:
            selectedFilter = .all
        case .thisMonth:
            selectedFilter = .all
            selectedPeriod = .thisMonth
        case .uncategorized:
            selectedFilter = .uncategorized
        case .needsReceipt, .cash:
            selectedFilter = .all
        }
        transactionPage = 0
    }

    private func refreshListSnapshot() {
        listSnapshot = TransactionListSnapshot.make(
            index: store.ledgerIndex,
            filter: selectedFilter,
            period: selectedPeriod,
            quickFilter: selectedQuickFilter,
            searchText: searchText,
            customStartDate: customStartDate,
            customEndDate: customEndDate,
            page: transactionPage,
            pageSize: transactionsPerPage
        )
    }

    @ViewBuilder
    private var transactionPagination: some View {
        if listSnapshot.pageCount > 1 {
            HStack(spacing: 16) {
                Button {
                    transactionPage = max(0, listSnapshot.displayedPage - 1)
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .disabled(listSnapshot.displayedPage == 0)

                Text("Page \(listSnapshot.displayedPage + 1) of \(listSnapshot.pageCount)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(PocketLedgerTheme.textSecondary)

                Button {
                    transactionPage = min(listSnapshot.pageCount - 1, listSnapshot.displayedPage + 1)
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(listSnapshot.displayedPage == listSnapshot.pageCount - 1)
            }
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    private var transactionsSummary: some View {
        let expenses = listSnapshot.expenseTotals

        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedPeriod.rawValue)
                        .font(.headline)
                    Text("Filtered overview")
                        .font(.caption)
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                }

                Spacer()

                Text("\(listSnapshot.filteredTransactions.count) shown")
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
                .font(.caption2.weight(.bold))
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
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
            }
            .frame(width: 46, height: 46)
            .pocketGlassSurface(cornerRadius: 13, tint: PocketLedgerTheme.surfaceElevated.opacity(0.22))

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
    @State private var isShowingDeleteConfirmation = false
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onSaveTemplate: () -> Void
    let allowsActions: Bool
    let isSelectionMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void

    init(
        transaction: LedgerTransaction,
        store: LedgerStore,
        onEdit: @escaping () -> Void,
        onDuplicate: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onSaveTemplate: @escaping () -> Void,
        allowsActions: Bool,
        isSelectionMode: Bool = false,
        isSelected: Bool = false,
        onToggleSelection: @escaping () -> Void = {}
    ) {
        self.transaction = transaction
        self.store = store
        self.onEdit = onEdit
        self.onDuplicate = onDuplicate
        self.onDelete = onDelete
        self.onSaveTemplate = onSaveTemplate
        self.allowsActions = allowsActions
        self.isSelectionMode = isSelectionMode
        self.isSelected = isSelected
        self.onToggleSelection = onToggleSelection
    }

    var body: some View {
        Button(action: isSelectionMode ? onToggleSelection : onEdit) {
            rowContent
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(transaction.note), \(rowSubtitle), \(amountText)")
        .accessibilityHint(isSelectionMode ? "Toggles transaction selection" : "Opens transaction details")
        .contextMenu {
            if allowsActions {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
                Button("Save as template", systemImage: "rectangle.stack.badge.plus", action: onSaveTemplate)
                Button("Delete", systemImage: "trash", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if allowsActions {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
                Button("Edit", systemImage: "pencil", action: onEdit)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if allowsActions {
                Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
                    .tint(PocketLedgerTheme.accent)
                Button("Template", systemImage: "rectangle.stack.badge.plus", action: onSaveTemplate)
                    .tint(PocketLedgerTheme.positive)
            }
        }
        .confirmationDialog(
            "Delete transaction?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(transaction.note)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? PocketLedgerTheme.accent : PocketLedgerTheme.textTertiary)
                    .accessibilityHidden(true)
            }

            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 38, height: 38)
                .pocketGlassSurface(cornerRadius: 19, tint: accentColor.opacity(0.12))

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.note)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(rowSubtitle)
                    .font(.caption)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                    .lineLimit(2)

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
    }

    private var rowSubtitle: String {
        let detail = transaction.kind == .expense
            ? store.categoryPath(for: transaction.categoryID)
            : transaction.kind.displayName
        return "\(detail) · \(transaction.date.formatted(date: .omitted, time: .shortened))"
    }

    private var iconName: String {
        if transaction.categoryID != nil {
            return store.ledgerIndex.categorySystemImage(for: transaction.categoryID)
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
    @State private var editingAccount: Account?

    var body: some View {
        List {
            screenSubtitle
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            globalPositionSummary
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            ForEach(AccountType.allCases) { accountType in
                let accounts = store.activeAccounts.filter { $0.type == accountType }
                if !accounts.isEmpty {
                    accountSection(type: accountType, accounts: accounts)
                }
            }

            if !archivedAccounts.isEmpty {
                archivedAccountsSection
            }

            Text(store.storageAvailable && store.sharedStorageAvailable
                 ? "Stored locally in the shared app container."
                 : store.storageAvailable
                 ? "Stored persistently on this device; widget sharing is unavailable."
                 : "Persistent storage is unavailable; changes cannot be saved.")
                .font(.caption)
                .foregroundStyle(PocketLedgerTheme.textTertiary)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 20, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .pocketScreen()
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentAccount(nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add account")
            }
        }
        .sheet(isPresented: $isPresentingAccount, onDismiss: { editingAccount = nil }) {
            AccountEditor(store: store, account: editingAccount)
        }
    }

    private var globalPositionSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Global position")
                        .font(.title3.weight(.bold))
                    Text("Assets, liabilities, and net total by currency")
                        .font(.caption)
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(PocketLedgerTheme.accent)
            }

            VStack(spacing: 0) {
                ForEach(LedgerCurrency.allCases) { currency in
                    if currency != LedgerCurrency.allCases[0] {
                        Divider().overlay(PocketLedgerTheme.divider)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(currency.rawValue)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PocketLedgerTheme.textSecondary)

                        accountPositionRow(
                            title: "Assets",
                            value: store.assetBalance(for: currency),
                            tint: PocketLedgerTheme.income
                        )
                        accountPositionRow(
                            title: "Liabilities",
                            value: store.liabilityBalance(for: currency),
                            tint: PocketLedgerTheme.warning
                        )
                        accountPositionRow(
                            title: "Total",
                            value: store.netWorth(for: currency),
                            tint: PocketLedgerTheme.textPrimary,
                            isEmphasized: true
                        )
                    }
                    .padding(.vertical, 10)
                }
            }
        }
        .pocketCard()
    }

    private func accountPositionRow(
        title: String,
        value: Money,
        tint: Color,
        isEmphasized: Bool = false
    ) -> some View {
        HStack {
            Text(title)
                .font(isEmphasized ? .subheadline.weight(.semibold) : .caption)
                .foregroundStyle(isEmphasized ? PocketLedgerTheme.textPrimary : PocketLedgerTheme.textSecondary)

            Spacer()

            Text(value.formatted)
                .font(
                    isEmphasized
                        ? Font.subheadline.weight(.semibold).monospacedDigit()
                        : Font.caption.weight(.semibold).monospacedDigit()
                )
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    private var screenSubtitle: some View {
        Text("Tap an account for activity; use its menu to manage or reorder it")
            .font(.subheadline)
            .foregroundStyle(PocketLedgerTheme.textSecondary)
    }

    private func accountSection(type: AccountType, accounts: [Account]) -> some View {
        Section {
            ForEach(accounts) { account in
                let accountPosition = accounts.firstIndex(where: { $0.id == account.id }) ?? 0
                HStack(spacing: 4) {
                    NavigationLink {
                        AccountDetailView(store: store, accountID: account.id)
                    } label: {
                        AccountRow(account: account, balance: store.balance(for: account))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Menu {
                        Button("Edit", systemImage: "pencil") {
                            presentAccount(account)
                        }
                        Button(
                            account.includeInTotals ? "Exclude from totals" : "Include in totals",
                            systemImage: account.includeInTotals ? "eye.slash" : "eye"
                        ) {
                            _ = store.setAccountIncludedInTotals(
                                accountID: account.id,
                                included: !account.includeInTotals
                            )
                        }
                        Button("Move up", systemImage: "chevron.up") {
                            _ = store.moveAccount(accountID: account.id, by: -1)
                        }
                        .disabled(accountPosition == 0)
                        Button("Move down", systemImage: "chevron.down") {
                            _ = store.moveAccount(accountID: account.id, by: 1)
                        }
                        .disabled(accountPosition == accounts.count - 1)
                        Button("Archive", systemImage: "archivebox") {
                            _ = store.setAccountArchived(accountID: account.id, isArchived: true)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(PocketLedgerTheme.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Actions for \(account.name)")
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Edit", systemImage: "pencil") {
                        presentAccount(account)
                    }
                    Button("Archive", systemImage: "archivebox") {
                        _ = store.setAccountArchived(accountID: account.id, isArchived: true)
                    }
                    .tint(PocketLedgerTheme.warning)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button(
                        account.includeInTotals ? "Exclude" : "Include",
                        systemImage: account.includeInTotals ? "eye.slash" : "eye"
                    ) {
                        _ = store.setAccountIncludedInTotals(
                            accountID: account.id,
                            included: !account.includeInTotals
                        )
                    }
                    .tint(account.includeInTotals ? PocketLedgerTheme.textSecondary : PocketLedgerTheme.positive)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(PocketLedgerTheme.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(PocketLedgerTheme.divider, lineWidth: 1)
                        }
                )
                .listRowSeparator(.hidden)
            }
        } header: {
            HStack(spacing: 8) {
                Image(systemName: type.systemImage)
                    .foregroundStyle(PocketLedgerTheme.accent)
                Text(type.displayName)
                    .font(.caption.weight(.bold))
                Text("\(accounts.count) \(accounts.count == 1 ? "account" : "accounts")")
                    .font(.caption)
                    .foregroundStyle(PocketLedgerTheme.textTertiary)
            }
            .textCase(nil)
        }
    }

    private var archivedAccounts: [Account] {
        store.data.accounts.filter(\.isArchived)
    }

    private var archivedAccountsSection: some View {
        Section {
            ForEach(archivedAccounts) { account in
                HStack(spacing: 12) {
                    PocketIcon(
                        systemImage: account.type.systemImage,
                        tint: PocketLedgerTheme.textTertiary,
                        size: 34
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name)
                            .font(.subheadline.weight(.semibold))
                        Text("\(account.type.displayName) · \(account.currency.rawValue)")
                            .font(.caption)
                            .foregroundStyle(PocketLedgerTheme.textTertiary)
                    }

                    Spacer(minLength: 8)

                    Button("Restore", systemImage: "arrow.uturn.backward") {
                        _ = store.setAccountArchived(accountID: account.id, isArchived: false)
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button("Restore", systemImage: "arrow.uturn.backward") {
                        _ = store.setAccountArchived(accountID: account.id, isArchived: false)
                    }
                    .tint(PocketLedgerTheme.accent)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(PocketLedgerTheme.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(PocketLedgerTheme.divider, lineWidth: 1)
                        }
                )
                .listRowSeparator(.hidden)
            }
        } header: {
            Text("Archived")
                .font(.title3.weight(.bold))
                .textCase(nil)
        } footer: {
            Text("Archived accounts stay available for historical transactions but are hidden from new account selections.")
                .font(.caption)
                .foregroundStyle(PocketLedgerTheme.textSecondary)
        }
    }

    private func presentAccount(_ account: Account?) {
        editingAccount = account
        isPresentingAccount = true
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
                if account.isArchived {
                    Text("Archived")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(PocketLedgerTheme.textTertiary)
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
    @State private var editingCategory: LedgerCategory?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                    screenSubtitle

                    ForEach(store.rootCategories) { parent in
                        categoryGroup(parent)
                    }

                    if !archivedCategories.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Archived")
                                .font(.title3.weight(.bold))
                            ForEach(archivedCategories) { category in
                                HStack {
                                    Label(category.name, systemImage: category.systemImage)
                                    Spacer()
                                    Button("Restore") {
                                        _ = store.setCategoryArchived(categoryID: category.id, isArchived: false)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .font(.subheadline)
                            }
                        }
                        .pocketCard()
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
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentCategory(nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add category")
            }
        }
        .sheet(isPresented: $isPresentingCategory, onDismiss: { editingCategory = nil }) {
            CategoryEditor(store: store, category: editingCategory)
        }
    }

    private var screenSubtitle: some View {
        Text("Make every expense easy to understand")
            .font(.subheadline)
            .foregroundStyle(PocketLedgerTheme.textSecondary)
    }

    private func categoryGroup(_ parent: LedgerCategory) -> some View {
        let children = store.data.categories.filter { $0.parentID == parent.id && !$0.isArchived }

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

                Menu {
                    Button("Edit", systemImage: "pencil") {
                        presentCategory(parent)
                    }
                    Button("Archive", systemImage: "archivebox") {
                        _ = store.setCategoryArchived(categoryID: parent.id, isArchived: true)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Category actions")
                .accessibilityHint("Opens actions for this category")
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
                        CategoryTile(
                            category: child,
                            onEdit: { presentCategory(child) },
                            onArchive: {
                                _ = store.setCategoryArchived(categoryID: child.id, isArchived: true)
                            }
                        )
                    }
                }
            }
        }
        .pocketCard()
    }

    private var archivedCategories: [LedgerCategory] {
        store.data.categories.filter(\.isArchived)
    }

    private func presentCategory(_ category: LedgerCategory?) {
        editingCategory = category
        isPresentingCategory = true
    }
}

private struct CategoryTile: View {
    let category: LedgerCategory
    let onEdit: () -> Void
    let onArchive: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: category.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                Spacer()

                Menu {
                    Button("Edit", systemImage: "pencil", action: onEdit)
                    Button("Archive", systemImage: "archivebox", action: onArchive)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Actions for \(category.name)")
            }

            Text(category.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(PocketLedgerTheme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .pocketGroupedSurface(cornerRadius: 13)
    }
}

@MainActor
struct AccountEditor: View {
    @ObservedObject var store: LedgerStore
    let account: Account?
    let initialCurrency: LedgerCurrency?
    let onSaved: (Account) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type: AccountType = .cash
    @State private var currency: LedgerCurrency = .usd
    @State private var openingBalance = "0"
    @State private var includeInTotals = true
    @State private var errorMessage: String?

    init(
        store: LedgerStore,
        account: Account? = nil,
        initialCurrency: LedgerCurrency? = nil,
        onSaved: @escaping (Account) -> Void = { _ in }
    ) {
        _store = ObservedObject(wrappedValue: store)
        self.account = account
        self.initialCurrency = initialCurrency
        self.onSaved = onSaved
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.type ?? .cash)
        _currency = State(initialValue: account?.currency ?? initialCurrency ?? .usd)
        _openingBalance = State(
            initialValue: account.map {
                NSDecimalNumber(
                    decimal: Decimal($0.openingBalance.minorUnits) / Decimal($0.currency.minorUnitScale)
                ).stringValue
            } ?? "0"
        )
        _includeInTotals = State(initialValue: account?.includeInTotals ?? true)
    }

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
                    if hasActivity {
                        Text("Changing currency updates this account's opening balance and all related transactions. Amounts keep their displayed numeric value; no exchange-rate conversion is applied.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Include in totals and metrics", isOn: $includeInTotals)
                    Text("Turn this off for assets or investments you want to track separately.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Opening balance") {
                    CurrencyInputField("Amount", text: $openingBalance, currency: currency)
                    Text("The amount is stored in the account's own currency.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .pocketScreen()
            .listRowBackground(Color.clear)
            .tint(PocketLedgerTheme.accent)
            .navigationTitle(account == nil ? "New account" : "Edit account")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: currency) { oldCurrency, newCurrency in
                guard let account, oldCurrency != newCurrency,
                      let balance = Money.parse(openingBalance, currency: oldCurrency) else {
                    return
                }
                let migratedBalance = balance.recast(to: newCurrency)
                openingBalance = NSDecimalNumber(
                    decimal: Decimal(migratedBalance.minorUnits)
                        / Decimal(newCurrency.minorUnitScale)
                ).stringValue
            }
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

        let value = Account(
            id: account?.id ?? UUID(),
            name: trimmedName,
            type: type,
            currency: currency,
            openingBalance: balance,
            includeInTotals: includeInTotals,
            isArchived: account?.isArchived ?? false
        )
        let saved = account == nil ? store.addAccount(value) : store.updateAccount(value)
        guard saved else {
            errorMessage = store.lastActionStatus ?? "The account could not be saved."
            return
        }
        onSaved(value)
        dismiss()
    }

    private var hasActivity: Bool {
        guard let account else { return false }
        return store.data.transactions.contains {
            ($0.outflows + $0.inflows).contains { $0.accountID == account.id }
        } || store.data.scheduledTransactions.contains {
            ($0.outflows + $0.inflows).contains { $0.accountID == account.id }
        }
    }
}

@MainActor
private struct CategoryEditor: View {
    @ObservedObject var store: LedgerStore
    let category: LedgerCategory?
    let onSaved: (LedgerCategory) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var parentID: UUID?
    @State private var systemImage = "tag"
    @State private var includeInTotals = true
    @State private var errorMessage: String?

    init(
        store: LedgerStore,
        category: LedgerCategory? = nil,
        onSaved: @escaping (LedgerCategory) -> Void = { _ in }
    ) {
        _store = ObservedObject(wrappedValue: store)
        self.category = category
        self.onSaved = onSaved
        _name = State(initialValue: category?.name ?? "")
        _parentID = State(initialValue: category?.parentID)
        _systemImage = State(initialValue: category?.systemImage ?? "tag")
        _includeInTotals = State(initialValue: category?.includeInTotals ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    TextField("Name", text: $name)
                    Picker("Parent category", selection: $parentID) {
                        Text("Top-level category").tag(UUID?.none)
                        ForEach(store.rootCategories.filter { $0.id != self.category?.id }) { parent in
                            Text(parent.name).tag(Optional(parent.id))
                        }
                    }
                    TextField("SF Symbol", text: $systemImage)
                    Toggle("Include in totals and metrics", isOn: $includeInTotals)
                    Text(includeInTotals
                         ? "Expenses in this category count toward totals and metrics."
                         : "Expenses in this category are kept in the ledger but excluded from totals and metrics.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .pocketScreen()
            .listRowBackground(Color.clear)
            .tint(PocketLedgerTheme.accent)
            .navigationTitle(category == nil ? "New category" : "Edit category")
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
        let value = LedgerCategory(
            id: category?.id ?? UUID(),
            name: trimmedName,
            parentID: parentID,
            systemImage: trimmedSymbol.isEmpty ? "tag" : trimmedSymbol,
            includeInTotals: includeInTotals,
            isArchived: category?.isArchived ?? false
        )
        let saved = category == nil ? store.addCategory(value) : store.updateCategory(value)
        guard saved else {
            errorMessage = store.lastActionStatus ?? "The category could not be saved."
            return
        }
        onSaved(value)
        dismiss()
    }
}

private struct MovementDraft: Identifiable, Equatable {
    let id = UUID()
    var accountID: UUID
    var currency: LedgerCurrency
    var amount: String
}

@MainActor
private struct MovementLineEditor: View {
    @ObservedObject var store: LedgerStore
    @Binding var line: MovementDraft
    let amountPlaceholder: String
    let onCreateAccount: () -> Void
    let allowsArchivedAccount: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CurrencyInputField(amountPlaceholder, text: $line.amount, currency: line.currency)

            HStack {
                Picker("Account", selection: $line.accountID) {
                    ForEach(store.data.accounts.filter { account in
                        !account.isArchived || (allowsArchivedAccount && account.id == line.accountID)
                    }) { account in
                        Text("\(account.name) (\(account.currency.rawValue))")
                            .tag(account.id)
                    }
                }
                .pickerStyle(.menu)

                Button("New account", systemImage: "plus.circle", action: onCreateAccount)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("New account")
                    .buttonStyle(.borderless)
            }

            HStack {
                Text("Currency")
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                Spacer()
                Menu {
                    ForEach(LedgerCurrency.allCases) { currency in
                        Button {
                            line.currency = currency
                        } label: {
                            if currency == line.currency {
                                Label(currency.rawValue, systemImage: "checkmark")
                            } else {
                                Text(currency.rawValue)
                            }
                        }
                    }
                } label: {
                    Label(line.currency.rawValue, systemImage: "chevron.up.chevron.down")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Payment currency")
                .accessibilityValue(Text(line.currency.rawValue))
            }
        }
    }
}

@MainActor
struct TransactionEditor: View {
    private static let lastAccountKey = "pocketLedger.lastTransactionAccount"
    private static let lastCategoryKey = "pocketLedger.lastExpenseCategory"

    @ObservedObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var date = Date.now
    @State private var kind: TransactionKind = .expense
    @State private var timing: TransactionTiming = .now
    @State private var scheduleFrequency: ScheduleFrequency = .once
    @State private var monthlyRule: ScheduleMonthlyRule = .dayOfMonth
    @State private var scheduleEnabled = true
    @State private var categoryID: UUID?
    @State private var dueCurrency: LedgerCurrency = .usd
    @State private var amountDue = ""
    @State private var outflows: [MovementDraft]
    @State private var inflows: [MovementDraft] = []
    @State private var requestedChange = ""
    @State private var useCustomRate = true
    @State private var automaticTransferDestinationAmount: String?
    @State private var rateBase: LedgerCurrency = .usd
    @State private var rateQuote: LedgerCurrency = .lbp
    @State private var rateText = "100000"
    @State private var attachmentIDs: [UUID]
    @State private var previewAttachment: LedgerAttachment?
    @State private var isShowingAttachmentImporter = false
    @State private var replacingAttachmentID: UUID?
    @State private var isShowingNewAccount = false
    @State private var isShowingNewCategory = false
    @State private var accountCreationLineID: UUID?
    @State private var errorMessage: String?
    @State private var isShowingMoreDetails = false
    @State private var saveFeedbackTrigger = 0
    private let editingScheduleID: UUID?
    private let editingScheduleLastRunDate: Date?
    private let editingScheduleNextRunDate: Date?
    private let editingScheduleFrequency: ScheduleFrequency?
    private let editingScheduleRecurrenceDay: Int?
    private let editingScheduleReminderTiming: ScheduledReminderTiming?
    private let editingTransactionID: UUID?
    private let initialAttachmentData: Data?
    private let initialAttachmentFileName: String?
    private let initialAttachmentContentType: String?
    private let initialReceiptItems: [LedgerReceiptLineItem]

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
        prefilledTransaction: LedgerTransaction? = nil,
        template: LedgerTemplate? = nil,
        initialAttachmentData: Data? = nil,
        initialAttachmentFileName: String? = nil,
        initialAttachmentContentType: String? = nil,
        initialReceiptItems: [LedgerReceiptLineItem] = []
    ) {
        _store = ObservedObject(wrappedValue: store)
        let sourceTransaction = transaction ?? prefilledTransaction ?? template?.transactionTemplate
        let rememberedAccount = UserDefaults.standard.string(forKey: Self.lastAccountKey)
            .flatMap(UUID.init(uuidString:))
            .flatMap { id in store.activeAccounts.first(where: { $0.id == id }) }
        let preferredCurrency = sourceTransaction?.outflows.first?.money.currency
            ?? sourceTransaction?.inflows.first?.money.currency
            ?? scheduledTransaction?.outflows.first?.money.currency
            ?? scheduledTransaction?.inflows.first?.money.currency
            ?? initialAmount?.currency
            ?? rememberedAccount?.currency
        let firstAccount = store.activeAccounts.first { account in
            guard let preferredCurrency else { return true }
            return account.currency == preferredCurrency
        } ?? rememberedAccount ?? store.activeAccounts.first
        let firstAccountID = firstAccount?.id ?? UUID()
        let resolvedInitialKind = sourceTransaction?.kind ?? scheduledTransaction?.kind ?? initialKind
        let initialDestinationAccount = store.activeAccounts.first { account in
            account.id != firstAccountID
        } ?? firstAccount
        let initialDestinationAccountID = initialDestinationAccount?.id ?? firstAccountID
        let amountDue = sourceTransaction?.amountDue ?? scheduledTransaction?.amountDue ?? initialBillTotal
        let initialCurrencies = LedgerCurrency.allCases.filter { currency in
            let initialOutflows = sourceTransaction?.outflows ?? scheduledTransaction?.outflows ?? []
            let initialInflows = sourceTransaction?.inflows ?? scheduledTransaction?.inflows ?? []
            return initialOutflows.contains { $0.money.currency == currency }
                || initialInflows.contains { $0.money.currency == currency }
                || initialOutflows.contains { store.account(with: $0.accountID)?.currency == currency }
                || initialInflows.contains { store.account(with: $0.accountID)?.currency == currency }
                || (resolvedInitialKind == .transfer && [
                    firstAccount?.currency,
                    initialDestinationAccount?.currency
                ].compactMap { $0 }.contains(currency))
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
        let sourceCategoryID = sourceTransaction?.categoryID
        let initialCategoryID = transaction != nil
            ? sourceCategoryID
            : sourceCategoryID.flatMap { id in
                store.activeCategories.contains { $0.id == id } ? id : nil
            }
        _note = State(initialValue: sourceTransaction?.note ?? scheduledTransaction?.note ?? initialNote ?? "")
        _date = State(initialValue: transaction?.date ?? scheduledTransaction?.nextRunDate ?? .now)
        _kind = State(initialValue: resolvedInitialKind)
        _timing = State(initialValue: transaction == nil && scheduledTransaction == nil ? initialTiming : transaction == nil ? .scheduled : .now)
        _scheduleFrequency = State(initialValue: scheduledTransaction?.frequency ?? initialFrequency)
        _monthlyRule = State(initialValue: scheduledTransaction?.monthlyRule ?? .dayOfMonth)
        _scheduleEnabled = State(initialValue: scheduledTransaction?.isEnabled ?? true)
        _dueCurrency = State(initialValue: amountDue?.currency ?? preferredCurrency ?? .usd)
        _amountDue = State(initialValue: amountDue.map { Self.inputText(for: $0) } ?? "")
        _outflows = State(
            initialValue: (sourceTransaction?.outflows ?? scheduledTransaction?.outflows)?.map {
                MovementDraft(
                    accountID: $0.accountID,
                    currency: $0.money.currency,
                    amount: Self.inputText(for: $0.money)
                )
            } ?? [
                MovementDraft(
                    accountID: firstAccountID,
                    currency: initialAmount?.currency ?? firstAccount?.currency ?? preferredCurrency ?? .usd,
                    amount: initialAmount.map { Self.inputText(for: $0) } ?? ""
                )
            ]
        )
        _inflows = State(
            initialValue: (sourceTransaction?.inflows ?? scheduledTransaction?.inflows)?.map {
                MovementDraft(
                    accountID: $0.accountID,
                    currency: $0.money.currency,
                    amount: Self.inputText(for: $0.money)
                )
            } ?? (resolvedInitialKind == .transfer
                ? [
                    MovementDraft(
                        accountID: initialDestinationAccountID,
                        currency: initialDestinationAccount?.currency ?? .usd,
                        amount: ""
                    )
                ]
                : [])
        )
        let initialOutflows = sourceTransaction?.outflows ?? scheduledTransaction?.outflows ?? []
        let initialInflows = sourceTransaction?.inflows ?? scheduledTransaction?.inflows ?? []
        let initialHasAttachments = !(transaction?.attachmentIDs ?? []).isEmpty
            || initialAttachmentData != nil
        _isShowingMoreDetails = State(initialValue:
            resolvedInitialKind != .expense
                || initialTiming == .scheduled
                || scheduledTransaction != nil
                || initialOutflows.count > 1
                || !initialInflows.isEmpty
                || sourceTransaction?.changeAdjustment != nil
                || sourceTransaction?.exchangeRate != nil
                || scheduledTransaction?.exchangeRate != nil
                || amountDue != nil
                || initialHasAttachments
                || initialCurrencies.count > 1
                || !initialReceiptItems.isEmpty
        )
        _requestedChange = State(
            initialValue: (sourceTransaction?.changeAdjustment ?? scheduledTransaction?.changeAdjustment).map { Self.inputText(for: $0.requested) } ?? ""
        )
        _rateBase = State(initialValue: initialRateBase)
        _rateQuote = State(initialValue: initialRateQuote)
        _useCustomRate = State(
            initialValue: resolvedInitialKind == .transfer
                ? sourceTransaction?.exchangeRate != nil
                    || scheduledTransaction?.exchangeRate != nil
                : true
        )
        _rateText = State(
            initialValue: initialSavedRate.map {
                NSDecimalNumber(decimal: $0.quoteUnitsPerBaseUnit).stringValue
            } ?? "100000"
        )
        _attachmentIDs = State(initialValue: transaction?.attachmentIDs ?? [])
        _categoryID = State(
            initialValue: initialCategoryID
                ?? scheduledTransaction?.categoryID
                ?? UserDefaults.standard.string(forKey: Self.lastCategoryKey)
                    .flatMap(UUID.init(uuidString:))
                    .flatMap { id in store.activeCategories.first(where: { $0.id == id })?.id }
                ?? store.activeCategories.first(where: { $0.parentID != nil })?.id
                ?? store.activeCategories.first?.id
        )
        editingScheduleID = scheduledTransaction?.id
        editingScheduleLastRunDate = scheduledTransaction?.lastRunDate
        editingScheduleNextRunDate = scheduledTransaction?.nextRunDate
        editingScheduleFrequency = scheduledTransaction?.frequency
        editingScheduleRecurrenceDay = scheduledTransaction?.recurrenceDay
        editingScheduleReminderTiming = scheduledTransaction?.reminderTiming
        editingTransactionID = transaction?.id
        self.initialAttachmentData = initialAttachmentData
        self.initialAttachmentFileName = initialAttachmentFileName
        self.initialAttachmentContentType = initialAttachmentContentType
        self.initialReceiptItems = initialReceiptItems
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

                if kind == .expense {
                    primaryExpenseMovementSection
                    detailsSection
                    expenseDateSection
                    moreDetailsSection
                } else {
                    timingSection
                    detailsSection
                    attachmentSection
                    outgoingMovementSection
                    receivingMovementSection
                    exchangeRateSection
                }
            }
            .onAppear {
                if kind == .transfer && inflows.isEmpty {
                    inflows.append(newReceivingMovementDraft)
                }
                synchronizeRatePair()
                synchronizeAutomaticTransferAmount()
            }
            .onChange(of: kind) { _, newKind in
                handleKindChange(newKind)
            }
            .onChange(of: selectedCurrencies) { _, _ in
                if kind == .expense && selectedCurrencies.count > 1 {
                    isShowingMoreDetails = true
                }
                synchronizeRatePair()
                synchronizeAutomaticTransferAmount()
            }
            .onChange(of: outflows) { _, newOutflows in
                if kind == .expense && newOutflows.count > 1 {
                    isShowingMoreDetails = true
                }
                synchronizeAutomaticTransferAmount()
            }
            .onChange(of: inflows) { oldInflows, newInflows in
                if kind == .expense && !newInflows.isEmpty {
                    isShowingMoreDetails = true
                }
                let amountWasEdited = oldInflows.first?.amount != newInflows.first?.amount
                if amountWasEdited,
                   newInflows.first?.amount != automaticTransferDestinationAmount {
                    self.automaticTransferDestinationAmount = nil
                    synchronizeRatePair()
                    return
                }
                synchronizeRatePair()
                synchronizeAutomaticTransferAmount()
            }
            .onChange(of: useCustomRate) { _, _ in
                if useCustomRate {
                    prepareCustomRate()
                }
                synchronizeAutomaticTransferAmount()
            }
            .onChange(of: rateText) { _, _ in
                guard useCustomRate else { return }
                synchronizeAutomaticTransferAmount()
            }
            .scrollContentBackground(.hidden)
            .pocketScreen()
            .listRowBackground(Color.clear)
            .tint(PocketLedgerTheme.accent)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.success, trigger: saveFeedbackTrigger)
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
            .sheet(item: $previewAttachment) { attachment in
                NavigationStack {
                    AttachmentPreviewView(store: store, attachment: attachment)
                }
            }
            .sheet(isPresented: $isShowingNewAccount) {
                AccountEditor(store: store) { account in
                    if let lineID = accountCreationLineID {
                        if let index = outflows.firstIndex(where: { $0.id == lineID }) {
                            outflows[index].accountID = account.id
                        }
                        if let index = inflows.firstIndex(where: { $0.id == lineID }) {
                            inflows[index].accountID = account.id
                        }
                    }
                    accountCreationLineID = nil
                }
            }
            .sheet(isPresented: $isShowingNewCategory) {
                CategoryEditor(store: store) { category in
                    categoryID = category.id
                }
            }
            .fileImporter(
                isPresented: $isShowingAttachmentImporter,
                allowedContentTypes: [.image, .pdf],
                allowsMultipleSelection: false,
                onCompletion: replaceAttachment
            )
        }
        .userActivity(
            "com.josephlteif.financedemo.viewing-transaction",
            element: visibleTransactionEntity
        ) { entity, activity in
            activity.title = "Viewing \(entity.note.isEmpty ? entity.kind : entity.note)"
            activity.appEntityIdentifier = EntityIdentifier(for: entity)
        }
    }

    private var visibleTransactionEntity: FinanceTransactionEntity? {
        guard let editingTransactionID,
              let transaction = store.data.transactions.first(where: { $0.id == editingTransactionID }) else {
            return nil
        }
        return FinanceTransactionEntity(transaction: transaction, data: store.data)
    }

    private var isEditingScheduledTransaction: Bool {
        editingScheduleID != nil
    }

    @ViewBuilder
    private var timingSection: some View {
        Section("Timing") {
            Picker("When", selection: $timing) {
                ForEach(TransactionTiming.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isEditingScheduledTransaction)

            if timing == .scheduled {
                DatePicker("First run", selection: $date, displayedComponents: [.date, .hourAndMinute])

                Picker("Repeats", selection: $scheduleFrequency) {
                    ForEach(ScheduleFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }

                if scheduleFrequency == .monthly {
                    Picker("Monthly rule", selection: $monthlyRule) {
                        ForEach(ScheduleMonthlyRule.allCases) { rule in
                            Text(rule.displayName).tag(rule)
                        }
                    }

                    Text(monthlyScheduleDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
    }

    private var primaryExpenseMovementSection: some View {
        Section("Payment 1") {
            if outflows.isEmpty {
                Button("Choose payment account", systemImage: "plus.circle") {
                    outflows.append(newMovementDraft)
                }
            } else {
                MovementLineEditor(
                    store: store,
                    line: $outflows[0],
                    amountPlaceholder: "Amount",
                    onCreateAccount: {
                        accountCreationLineID = outflows[0].id
                        isShowingNewAccount = true
                    },
                    allowsArchivedAccount: allowsArchivedMovementAccounts
                )

                if outflows.count > 1 {
                    Button("Remove payment", systemImage: "trash", role: .destructive) {
                        outflows.remove(at: 0)
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var expenseDateSection: some View {
        Section("Date") {
            DatePicker(
                timing == .scheduled ? "First run" : "Date",
                selection: $date,
                displayedComponents: timing == .scheduled ? [.date, .hourAndMinute] : [.date]
            )
        }
    }

    private var moreDetailsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isShowingMoreDetails) {
                VStack(alignment: .leading, spacing: 14) {
                    expenseScheduleDetails
                    Divider()
                    expenseBillDetails
                    Divider()
                    expenseSplitDetails
                    Divider()
                    expenseReturnedMoneyDetails
                    if !attachments.isEmpty || initialAttachmentFileName != nil {
                        Divider()
                        expenseAttachmentDetails
                    }
                    if selectedCurrencies.count > 1 {
                        Divider()
                        exchangeRateDetails
                    }
                }
                .padding(.vertical, 6)
            } label: {
                Label("More details", systemImage: "slider.horizontal.3")
            }
        }
    }

    private var expenseScheduleDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Schedule")
                .font(.subheadline.weight(.semibold))

            Picker("When", selection: $timing) {
                ForEach(TransactionTiming.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isEditingScheduledTransaction)

            if timing == .scheduled {
                Picker("Repeats", selection: $scheduleFrequency) {
                    ForEach(ScheduleFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }

                if scheduleFrequency == .monthly {
                    Picker("Monthly rule", selection: $monthlyRule) {
                        ForEach(ScheduleMonthlyRule.allCases) { rule in
                            Text(rule.displayName).tag(rule)
                        }
                    }

                    Text(monthlyScheduleDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Toggle("Enabled", isOn: $scheduleEnabled)
                    .disabled(completedOneTimeSchedule)

                if completedOneTimeSchedule {
                    Text("This one-time schedule has already been added to transactions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var expenseBillDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bill total")
                .font(.subheadline.weight(.semibold))

            HStack {
                Text("Bill currency")
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                Spacer()
                Menu {
                    ForEach(LedgerCurrency.allCases) { currency in
                        Button {
                            dueCurrency = currency
                        } label: {
                            if currency == dueCurrency {
                                Label(currency.rawValue, systemImage: "checkmark")
                            } else {
                                Text(currency.rawValue)
                            }
                        }
                    }
                } label: {
                    Label(dueCurrency.rawValue, systemImage: "chevron.up.chevron.down")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Bill total currency")
                .accessibilityValue(Text(dueCurrency.rawValue))
            }
            CurrencyInputField("Total due (optional)", text: $amountDue, currency: dueCurrency)
        }
    }

    private var expenseSplitDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Split payment")
                .font(.subheadline.weight(.semibold))

            ForEach(Array(outflows.dropFirst())) { movement in
                if let index = outflows.firstIndex(where: { $0.id == movement.id }) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Payment \(index + 1)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button(role: .destructive) {
                                outflows.remove(at: index)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .accessibilityLabel("Remove payment \(index + 1)")
                            .buttonStyle(.borderless)
                            .font(.footnote.weight(.semibold))
                        }

                        MovementLineEditor(
                            store: store,
                            line: $outflows[index],
                            amountPlaceholder: "Amount leaving account",
                            onCreateAccount: {
                                accountCreationLineID = movement.id
                                isShowingNewAccount = true
                            },
                            allowsArchivedAccount: allowsArchivedMovementAccounts
                        )
                    }
                    .padding(12)
                    .pocketGroupedSurface(cornerRadius: 14)
                }
            }

            Button {
                outflows.append(newSplitPaymentDraft)
            } label: {
                Label("Add another payment", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)

            Text("Each payment can use a different account and currency. The bill total is separate.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var expenseReturnedMoneyDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Returned money")
                .font(.subheadline.weight(.semibold))

            ForEach(Array(inflows)) { movement in
                if let index = inflows.firstIndex(where: { $0.id == movement.id }) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Return \(index + 1)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button(role: .destructive) {
                                inflows.remove(at: index)
                                if inflows.isEmpty { requestedChange = "" }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .accessibilityLabel("Remove returned money \(index + 1)")
                            .buttonStyle(.borderless)
                            .font(.footnote.weight(.semibold))
                        }

                        MovementLineEditor(
                            store: store,
                            line: $inflows[index],
                            amountPlaceholder: "Amount returned",
                            onCreateAccount: {
                                accountCreationLineID = movement.id
                                isShowingNewAccount = true
                            },
                            allowsArchivedAccount: allowsArchivedMovementAccounts
                        )
                    }
                    .padding(12)
                    .pocketGroupedSurface(cornerRadius: 14)
                }
            }

            Button {
                inflows.append(newReceivingMovementDraft)
            } label: {
                Label(
                    inflows.isEmpty ? "Add returned money" : "Add another receiving account",
                    systemImage: "arrow.down.circle"
                )
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)

            if inflows.count == 1 {
                CurrencyInputField(
                    "Requested change (optional)",
                    text: $requestedChange,
                    currency: inflows[0].currency
                )
                if let preview = shortfallPreview {
                    Text(preview)
                        .font(.footnote)
                        .foregroundStyle(PocketLedgerTheme.warning)
                }
            }

            Text("Returned money may go to a different account and currency than the payment.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var expenseAttachmentDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attachments")
                .font(.subheadline.weight(.semibold))

            ForEach(attachments) { attachment in
                HStack {
                    Button {
                        previewAttachment = attachment
                    } label: {
                        Label(
                            attachment.fileName,
                            systemImage: attachment.contentType == "application/pdf" ? "doc.richtext" : "photo"
                        )
                    }
                    .foregroundStyle(PocketLedgerTheme.textPrimary)

                    Spacer()

                    Button("Replace") {
                        beginReplacingAttachment(attachment)
                    }
                    .font(.footnote.weight(.semibold))
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        deleteAttachment(attachment)
                    }
                }
            }

            if attachments.isEmpty, let initialAttachmentFileName {
                Label(
                    initialAttachmentFileName,
                    systemImage: initialAttachmentContentType == "application/pdf" ? "doc.richtext" : "photo"
                )
                Text("This local file will be saved with the transaction.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        Section("Details") {
            if kind == .expense {
                HStack {
                    if selectableCategories.isEmpty {
                        Text("No categories yet — this expense will be Uncategorized.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Category", selection: $categoryID) {
                            CategoryPickerContent(categories: selectableCategories)
                        }
                    }

                    Button("New category", systemImage: "plus.circle") {
                        isShowingNewCategory = true
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("New category")
                }
            }

            TextField("What was this for?", text: $note)
        }
    }

    @ViewBuilder
    private var attachmentSection: some View {
        if !attachments.isEmpty {
            Section("Attachments") {
                ForEach(attachments) { attachment in
                    HStack {
                        Button {
                            previewAttachment = attachment
                        } label: {
                            Label(attachment.fileName, systemImage: attachment.contentType == "application/pdf" ? "doc.richtext" : "photo")
                        }
                        .foregroundStyle(PocketLedgerTheme.textPrimary)

                        Spacer()

                        Button(action: { beginReplacingAttachment(attachment) }) {
                            Text("Replace")
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            deleteAttachment(attachment)
                        }
                    }
                }
            }
        } else if let initialAttachmentFileName {
            Section("Receipt attachment") {
                Label(initialAttachmentFileName, systemImage: initialAttachmentContentType == "application/pdf" ? "doc.richtext" : "photo")
                Text("This local file will be saved with the transaction after you tap \(saveButtonTitle.lowercased()).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var allowsArchivedMovementAccounts: Bool {
        editingTransactionID != nil || editingScheduleID != nil
    }

    private var monthlyScheduleDescription: String {
        if monthlyRule == .lastDayOfMonth {
            return "This runs on the last calendar day of each month."
        }
        return "This keeps day \(Calendar.current.component(.day, from: date)) when the month has that day."
    }

    @ViewBuilder
    private var outgoingMovementSection: some View {
        if kind != .income {
            Section {
                ForEach($outflows) { $line in
                    MovementLineEditor(
                        store: store,
                        line: $line,
                        amountPlaceholder: kind == .transfer ? "Amount sent" : "Amount leaving account",
                        onCreateAccount: {
                            accountCreationLineID = $line.wrappedValue.id
                            isShowingNewAccount = true
                        },
                        allowsArchivedAccount: allowsArchivedMovementAccounts
                    )
                }
                .onDelete { outflows.remove(atOffsets: $0) }

                Button {
                    outflows.append(newMovementDraft)
                } label: {
                    Label("Add another account", systemImage: "plus.circle")
                }
            } header: {
                Text(kind == .transfer ? "From" : "Money leaving accounts")
            } footer: {
                Text(kind == .transfer
                     ? "Choose the account and amount sending the transfer."
                     : "Use one line for each currency or account used to pay.")
            }
        }
    }

    private var receivingMovementSection: some View {
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
                        amountPlaceholder: kind == .transfer ? "Amount received" : "Amount entering account",
                        onCreateAccount: {
                            accountCreationLineID = $line.wrappedValue.id
                            isShowingNewAccount = true
                        },
                        allowsArchivedAccount: allowsArchivedMovementAccounts
                    )
                }
                .onDelete { inflows.remove(atOffsets: $0) }

                Button {
                    inflows.append(newMovementDraft)
                } label: {
                    Label("Add another receiving account", systemImage: "plus.circle")
                }

                if kind == .expense && inflows.count == 1 {
                    CurrencyInputField(
                        "Requested change (optional)",
                        text: $requestedChange,
                        currency: inflows[0].currency
                    )
                    if let preview = shortfallPreview {
                        Text(preview)
                            .font(.footnote)
                            .foregroundStyle(PocketLedgerTheme.warning)
                    }
                }
            }
        } header: {
            Text(kind == .transfer
                 ? "To"
                 : kind == .expense ? "Change / money returned" : "Money entering accounts")
        } footer: {
            Text(kind == .transfer
                 ? "The amount is filled from the sending amount when possible. You can edit it for a specific transfer."
                 : kind == .expense
                    ? "Returned money may go to a different account and currency than the payment."
                    : "Choose the account and currency receiving the money.")
        }
    }

    @ViewBuilder
    private var exchangeRateSection: some View {
        if selectedCurrencies.count > 1 {
            Section("Exchange rate") {
                LabeledContent("Applied rate") {
                    Text(appliedExchangeRate?.summary ?? "Rate required")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(appliedExchangeRate == nil
                            ? PocketLedgerTheme.warning
                            : PocketLedgerTheme.textPrimary)
                        .multilineTextAlignment(.trailing)
                }

                Toggle(
                    kind == .transfer ? "Override for this transaction" : "Use a custom rate",
                    isOn: $useCustomRate
                )

                if !useCustomRate {
                    Text("The rate is calculated from the entered amounts, or uses the saved pair rate until both amounts are entered.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if useCustomRate {
                    Picker("Base", selection: $rateBase) {
                        ForEach(selectedCurrencies) { currency in
                            Text(currency.rawValue).tag(currency)
                        }
                    }
                    Picker("Quote", selection: $rateQuote) {
                        ForEach(selectedCurrencies) { currency in
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

    private var exchangeRateDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exchange rate")
                .font(.subheadline.weight(.semibold))

            LabeledContent("Applied rate") {
                Text(appliedExchangeRate?.summary ?? "Rate required")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(appliedExchangeRate == nil
                        ? PocketLedgerTheme.warning
                        : PocketLedgerTheme.textPrimary)
                    .multilineTextAlignment(.trailing)
            }

            Toggle("Use a custom rate", isOn: $useCustomRate)

            if !useCustomRate {
                Text("The rate is calculated from the entered amounts, or uses the saved pair rate until both amounts are entered.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if useCustomRate {
                Picker("Base", selection: $rateBase) {
                    ForEach(selectedCurrencies) { currency in
                        Text(currency.rawValue).tag(currency)
                    }
                }
                Picker("Quote", selection: $rateQuote) {
                    ForEach(selectedCurrencies) { currency in
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

    private var attachments: [LedgerAttachment] {
        attachmentIDs.compactMap { id in
            store.data.attachments.first(where: { $0.id == id })
        }
    }

    private func beginReplacingAttachment(_ attachment: LedgerAttachment) {
        replacingAttachmentID = attachment.id
        isShowingAttachmentImporter = true
    }

    private var selectableCategories: [LedgerCategory] {
        var categories = store.activeCategories
        if let categoryID,
           let category = store.ledgerIndex.categoriesByID[categoryID],
           !categories.contains(where: { $0.id == category.id }) {
            categories.append(category)
        }
        return categories
    }

    private func replaceAttachment(_ result: Result<[URL], Error>) {
        defer { replacingAttachmentID = nil }
        do {
            guard let attachmentID = replacingAttachmentID,
                  let url = try result.get().first else { return }
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            guard store.replaceAttachment(
                id: attachmentID,
                data: data,
                fileName: url.lastPathComponent,
                contentType: contentType
            ) else {
                errorMessage = store.lastActionStatus ?? "The attachment could not be replaced."
                return
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var newMovementDraft: MovementDraft {
        let account = store.activeAccounts.first
        return MovementDraft(
            accountID: account?.id ?? UUID(),
            currency: account?.currency ?? .usd,
            amount: ""
        )
    }

    private var newSplitPaymentDraft: MovementDraft {
        let usedAccountIDs = Set(outflows.map(\.accountID))
        let account = store.activeAccounts.first(where: { !usedAccountIDs.contains($0.id) })
            ?? store.activeAccounts.first
        return MovementDraft(
            accountID: account?.id ?? UUID(),
            currency: account?.currency ?? .usd,
            amount: ""
        )
    }

    private var newReceivingMovementDraft: MovementDraft {
        let sourceAccountIDs = Set(outflows.map(\.accountID))
        let account = store.activeAccounts.first(where: { !sourceAccountIDs.contains($0.id) })
            ?? store.activeAccounts.first
        return MovementDraft(
            accountID: account?.id ?? UUID(),
            currency: account?.currency ?? .usd,
            amount: ""
        )
    }

    private static func inputText(for money: Money) -> String {
        money.currency.formattedInput(minorUnits: money.minorUnits)
    }

    private var selectedCurrencies: [LedgerCurrency] {
        let drafts = (kind == .income ? [] : outflows) + inflows
        let currencies = Set(
            drafts.flatMap { draft in
                [
                    draft.currency,
                    store.account(with: draft.accountID)?.currency
                ].compactMap { $0 }
            }
        )
        return LedgerCurrency.allCases.filter { currencies.contains($0) }
    }

    private var savedRate: ExchangeRate? {
        store.exchangeRate(base: rateBase, quote: rateQuote)
    }

    private var rateCurrencyPair: (base: LedgerCurrency, quote: LedgerCurrency)? {
        if kind == .transfer,
           let sourceCurrency = outflows.first?.currency,
           let destinationCurrency = inflows.first?.currency,
           sourceCurrency != destinationCurrency {
            return (base: sourceCurrency, quote: destinationCurrency)
        }

        let drafts = (kind == .income ? [] : outflows) + inflows
        for draft in drafts {
            guard let accountCurrency = store.account(with: draft.accountID)?.currency,
                  accountCurrency != draft.currency else {
                continue
            }
            return (base: accountCurrency, quote: draft.currency)
        }

        let currencies = selectedCurrencies
        if currencies.count > 1 {
            return (base: currencies[0], quote: currencies[1])
        }
        return nil
    }

    private var parsedRateValue: Decimal? {
        Decimal(
            string: rateText.replacingOccurrences(of: ",", with: ""),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private var customExchangeRate: ExchangeRate? {
        guard rateBase != rateQuote,
              selectedCurrencies.contains(rateBase),
              selectedCurrencies.contains(rateQuote),
              let rate = parsedRateValue,
              rate > 0 else {
            return nil
        }
        return ExchangeRate(
            baseCurrency: rateBase,
            quoteCurrency: rateQuote,
            quoteUnitsPerBaseUnit: rate
        )
    }

    private var calculatedExchangeRate: ExchangeRate? {
        guard let pair = rateCurrencyPair,
              let parsedOutflows,
              let parsedInflows else {
            return nil
        }

        let parsedMovements = parsedOutflows + parsedInflows
        let sourceUnits = parsedMovements
            .filter { $0.money.currency == pair.base }
            .reduce(Decimal.zero) { total, movement in
                total + Decimal(movement.money.minorUnits) / Decimal(pair.base.minorUnitScale)
            }
        let destinationUnits = parsedMovements
            .filter { $0.money.currency == pair.quote }
            .reduce(Decimal.zero) { total, movement in
                total + Decimal(movement.money.minorUnits) / Decimal(pair.quote.minorUnitScale)
            }
        guard sourceUnits > 0, destinationUnits > 0 else { return nil }

        return ExchangeRate(
            baseCurrency: pair.base,
            quoteCurrency: pair.quote,
            quoteUnitsPerBaseUnit: destinationUnits / sourceUnits
        )
    }

    private var appliedExchangeRate: ExchangeRate? {
        guard let pair = rateCurrencyPair else { return nil }

        if useCustomRate {
            guard let customExchangeRate,
                  let rate = directedRate(
                      customExchangeRate.quoteUnitsPerBaseUnit,
                      from: customExchangeRate.baseCurrency,
                      to: customExchangeRate.quoteCurrency,
                      base: pair.base,
                      quote: pair.quote
                  ) else {
                return nil
            }
            return ExchangeRate(
                baseCurrency: pair.base,
                quoteCurrency: pair.quote,
                quoteUnitsPerBaseUnit: rate
            )
        }

        return calculatedExchangeRate
            ?? store.exchangeRate(base: pair.base, quote: pair.quote)
    }

    private func directedRate(
        _ value: Decimal,
        from sourceBase: LedgerCurrency,
        to sourceQuote: LedgerCurrency,
        base targetBase: LedgerCurrency,
        quote targetQuote: LedgerCurrency
    ) -> Decimal? {
        guard value > 0, sourceBase != sourceQuote, targetBase != targetQuote else {
            return nil
        }
        if sourceBase == targetBase && sourceQuote == targetQuote {
            return value
        }
        if sourceBase == targetQuote && sourceQuote == targetBase {
            return Decimal(1) / value
        }
        return nil
    }

    private static func money(
        units: Decimal,
        currency: LedgerCurrency
    ) -> Money? {
        guard units > 0 else { return nil }
        var scaled = units * Decimal(currency.minorUnitScale)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        let minorUnits = NSDecimalNumber(decimal: rounded).int64Value
        guard minorUnits > 0 else { return nil }
        return Money(currency: currency, minorUnits: minorUnits)
    }

    private func synchronizeRatePair() {
        let currencies = selectedCurrencies
        guard currencies.count > 1,
              !currencies.contains(rateBase) || !currencies.contains(rateQuote) || rateBase == rateQuote else {
            return
        }

        rateBase = currencies[0]
        rateQuote = currencies[1]
        if let savedRate {
            rateText = NSDecimalNumber(decimal: savedRate.quoteUnitsPerBaseUnit).stringValue
        }
    }

    private func handleKindChange(_ newKind: TransactionKind) {
        if newKind == .transfer && inflows.isEmpty {
            inflows.append(newReceivingMovementDraft)
        }
        if newKind != .transfer {
            automaticTransferDestinationAmount = nil
        }
        synchronizeRatePair()
        synchronizeAutomaticTransferAmount()
    }

    private func prepareCustomRate() {
        guard let pair = rateCurrencyPair else { return }
        rateBase = pair.base
        rateQuote = pair.quote
        if let rate = calculatedExchangeRate
            ?? store.exchangeRate(base: pair.base, quote: pair.quote) {
            rateText = NSDecimalNumber(decimal: rate.quoteUnitsPerBaseUnit).stringValue
        }
    }

    private func synchronizeAutomaticTransferAmount() {
        guard kind == .transfer else { return }

        guard outflows.count == 1,
              inflows.count == 1 else {
            clearAutomaticTransferAmount()
            return
        }

        guard let sourceAccount = store.account(with: outflows[0].accountID),
              let destinationAccount = store.account(with: inflows[0].accountID) else {
            clearAutomaticTransferAmount()
            return
        }

        let currentDestinationAmount = inflows[0].amount
        let canUpdate = currentDestinationAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || currentDestinationAmount == automaticTransferDestinationAmount
        guard canUpdate,
              let sourceMoney = Money.parse(outflows[0].amount, currency: outflows[0].currency),
              sourceMoney.minorUnits > 0 else {
            clearAutomaticTransferAmount()
            return
        }

        let destinationMoney: Money?
        if outflows[0].currency == inflows[0].currency {
            destinationMoney = sourceMoney
        } else {
            guard let rate = automaticTransferRate else {
                clearAutomaticTransferAmount()
                return
            }
            let sourceUnits = Decimal(sourceMoney.minorUnits) / Decimal(sourceMoney.currency.minorUnitScale)
            destinationMoney = Self.money(
                units: sourceUnits * rate,
                currency: inflows[0].currency
            )
        }

        guard let destinationMoney else {
            clearAutomaticTransferAmount()
            return
        }

        let amount = Self.inputText(for: destinationMoney)
        automaticTransferDestinationAmount = amount
        inflows[0].amount = amount
    }

    private func clearAutomaticTransferAmount() {
        if let automaticTransferDestinationAmount,
           inflows.count == 1,
           inflows[0].amount == automaticTransferDestinationAmount {
            inflows[0].amount = ""
        }
        automaticTransferDestinationAmount = nil
    }

    private var automaticTransferRate: Decimal? {
        guard let pair = rateCurrencyPair else { return nil }
        if useCustomRate {
            guard let customExchangeRate else { return nil }
            return directedRate(
                customExchangeRate.quoteUnitsPerBaseUnit,
                from: customExchangeRate.baseCurrency,
                to: customExchangeRate.quoteCurrency,
                base: pair.base,
                quote: pair.quote
            )
        }
        return store.exchangeRate(base: pair.base, quote: pair.quote)?.quoteUnitsPerBaseUnit
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
                  let requested = Money.parse(requestedChange, currency: inflows[0].currency),
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

        if selectedCurrencies.count > 1 {
            guard appliedExchangeRate != nil else { return false }
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
              let requested = Money.parse(requestedChange, currency: inflows[0].currency),
              let actual = Money.parse(inflows[0].amount, currency: inflows[0].currency) else {
            return nil
        }

        let difference = requested.minorUnits - actual.minorUnits
        if difference > 0 {
            return "Recorded denomination shortfall: \(Money(currency: inflows[0].currency, minorUnits: difference).formatted)."
        }
        if difference < 0 {
            return "Actual change is \(Money(currency: inflows[0].currency, minorUnits: -difference).formatted) above the requested amount."
        }
        return "The requested and actual change match."
    }

    private func parseMovements(_ drafts: [MovementDraft]) -> [MoneyMovement]? {
        let movements = drafts.compactMap { draft -> MoneyMovement? in
            guard let account = store.account(with: draft.accountID),
                  let money = Money.parse(draft.amount, currency: draft.currency),
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
        if selectedCurrencies.count > 1 {
            guard let appliedExchangeRate else {
                errorMessage = kind == .transfer
                    ? "Enter both transfer amounts or set a positive rate override."
                    : "Set a positive exchange rate for the different movement and account currencies."
                return
            }
            exchangeRate = appliedExchangeRate
        }

        var changeAdjustment: ChangeAdjustment?
        if kind == .expense,
           !requestedChange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           parsedInflows.count == 1,
           let requested = Money.parse(requestedChange, currency: inflows[0].currency) {
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

        guard !(timing == .scheduled && initialAttachmentData != nil) else {
            errorMessage = "Receipt attachments can only be saved with an immediate transaction. Switch When back to Now to keep this receipt."
            return
        }

        var newlySavedAttachment: LedgerAttachment?
        if timing != .scheduled,
           editingTransactionID == nil,
           let initialAttachmentData,
           let initialAttachmentFileName,
           let initialAttachmentContentType {
            guard let attachment = store.addAttachment(
                data: initialAttachmentData,
                fileName: initialAttachmentFileName,
                contentType: initialAttachmentContentType,
                receiptItems: initialReceiptItems,
                extractedTotal: parsedAmountDue
            ) else {
                errorMessage = store.lastActionStatus ?? "The receipt could not be attached."
                return
            }
            newlySavedAttachment = attachment
            attachmentIDs.append(attachment.id)
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
            changeAdjustment: changeAdjustment,
            attachmentIDs: attachmentIDs
        )

        if timing == .scheduled {
            let dateChanged = editingScheduleNextRunDate.map {
                !Calendar.current.isDate(date, inSameDayAs: $0)
            } ?? false
            let frequencyChanged = editingScheduleFrequency.map { $0 != scheduleFrequency } ?? false
            let recurrenceDay = dateChanged || editingScheduleRecurrenceDay == nil
                ? Calendar.current.component(.day, from: date)
                : editingScheduleRecurrenceDay!
            let lastRunDate = dateChanged || frequencyChanged ? nil : editingScheduleLastRunDate
            let enabled = lastRunDate != nil && scheduleFrequency == .once
                ? false
                : scheduleEnabled
            let scheduledTransaction = ScheduledTransaction(
                id: editingScheduleID ?? UUID(),
                nextRunDate: date,
                frequency: scheduleFrequency,
                monthlyRule: monthlyRule,
                recurrenceDay: recurrenceDay,
                isEnabled: enabled,
                reminderTiming: editingScheduleReminderTiming,
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

            let saved = editingScheduleID != nil
                ? store.updateScheduledTransaction(scheduledTransaction)
                : store.addScheduledTransaction(scheduledTransaction)
            guard saved else {
                errorMessage = store.lastActionStatus ?? "The schedule could not be saved."
                return
            }
        } else {
            let saved: Bool
            if editingTransactionID == nil {
                saved = store.addTransaction(transaction)
            } else {
                saved = store.updateTransaction(transaction)
            }
            guard saved else {
                if let newlySavedAttachment {
                    _ = store.deleteAttachment(id: newlySavedAttachment.id)
                }
                errorMessage = store.lastActionStatus ?? "The transaction could not be saved."
                return
            }
        }

        if let accountID = (parsedOutflows.first ?? parsedInflows.first)?.accountID {
            UserDefaults.standard.set(accountID.uuidString, forKey: Self.lastAccountKey)
        }
        if let categoryID, kind == .expense {
            UserDefaults.standard.set(categoryID.uuidString, forKey: Self.lastCategoryKey)
        }
        saveFeedbackTrigger += 1
        dismiss()
    }

    private func deleteAttachment(_ attachment: LedgerAttachment) {
        guard store.deleteAttachment(id: attachment.id) else { return }
        attachmentIDs.removeAll { $0 == attachment.id }
    }
}
