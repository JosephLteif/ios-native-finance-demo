import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
struct ContentView: View {
    @StateObject private var store = LedgerStore()
    @StateObject private var security = AppSecurityService()
    @State private var addAction: AddAction?
    @State private var isShowingSetup = false
    @State private var isShowingImportWizardUITest = false
    @State private var isUnlocked = false
    @SceneStorage("pocketLedger.selectedTab") private var selectedTabRawValue = AppTab.overview.rawValue
    @AppStorage(SetupWizardView.completedKey) private var setupCompleted = false
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
                if security.isPasscodeEnabled {
                    isUnlocked = false
                }
            }
        }
        .onChange(of: security.isPasscodeEnabled) { _, enabled in
            isUnlocked = !enabled
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("-ImportWizardUITest") {
                isShowingImportWizardUITest = true
                return
            }
            store.processDueScheduledTransactions()
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
                return tab == .transactions ? .more : tab
            },
            set: { tab in
                guard selectedTabRawValue != tab.rawValue else { return }
                withAnimation(.snappy(duration: 0.35)) {
                    selectedTabRawValue = tab.rawValue
                }
            }
        )
    }

    private func handleDeepLink(_ url: URL) {
        if let tab = AppTab(url: url) {
            selectedTabBinding.wrappedValue = tab == .transactions ? .more : tab
        }
    }

    private var unlockedContent: some View {
        NativeTabBarController(
            selectedTab: selectedTabBinding,
            store: store,
            security: security,
            onAddAction: { action in addAction = action }
        )
        .tint(PocketLedgerTheme.accent)
        .ignoresSafeArea()
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

@MainActor
private final class PocketLedgerTabBarController: UITabBarController {
    private let visibleTabBar = UITabBar()
    weak var addButton: UIButton?

    func installVisibleTabBar(items: [UITabBarItem], delegate: any UITabBarDelegate) {
        tabBar.isHidden = false
        tabBar.alpha = 0
        tabBar.isUserInteractionEnabled = false
        tabBar.accessibilityElementsHidden = true
        visibleTabBar.items = items
        visibleTabBar.delegate = delegate
        visibleTabBar.tintColor = UIColor(PocketLedgerTheme.accent)
        visibleTabBar.unselectedItemTintColor = UIColor(PocketLedgerTheme.textSecondary)
        visibleTabBar.isTranslucent = true
        visibleTabBar.accessibilityIdentifier = "main-tab-bar"
        if visibleTabBar.superview == nil {
            view.addSubview(visibleTabBar)
        }
    }

    func selectVisibleTab(at index: Int) {
        guard visibleTabBar.items?.indices.contains(index) == true else { return }
        visibleTabBar.selectedItem = visibleTabBar.items?[index]
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard visibleTabBar.superview != nil else { return }

        let systemTabBarFrame = tabBar.frame
        let tabBarHeight = max(49, systemTabBarFrame.height)
        let buttonSize: CGFloat = 56
        let buttonTrailing = view.bounds.width - view.safeAreaInsets.right - 16
        let tabBarCenterY = systemTabBarFrame.minY + tabBarHeight / 2
        let buttonFrame = CGRect(
            x: buttonTrailing - buttonSize,
            y: tabBarCenterY - buttonSize / 2,
            width: buttonSize,
            height: buttonSize
        )

        let gap: CGFloat = 12
        let tabBarFrame = CGRect(
            x: max(view.safeAreaInsets.left, 16),
            y: systemTabBarFrame.minY,
            width: max(0, buttonFrame.minX - gap - max(view.safeAreaInsets.left, 16)),
            height: tabBarHeight
        )
        visibleTabBar.frame = tabBarFrame
        addButton?.frame = buttonFrame
    }
}

@MainActor
private struct NativeTabBarController: UIViewControllerRepresentable {
    @Binding var selectedTab: AppTab
    @ObservedObject var store: LedgerStore
    @ObservedObject var security: AppSecurityService
    let onAddAction: (AddAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> PocketLedgerTabBarController {
        let controller = PocketLedgerTabBarController()
        controller.delegate = context.coordinator
        controller.setViewControllers(makeViewControllers(), animated: false)
        controller.selectedIndex = selectedTab.tabBarIndex
        controller.tabBar.tintColor = UIColor(PocketLedgerTheme.accent)

        if #available(iOS 26, *) {
            controller.tabBarMinimizeBehavior = .onScrollDown
            controller.installVisibleTabBar(
                items: makeVisibleTabBarItems(),
                delegate: context.coordinator
            )
            controller.selectVisibleTab(at: selectedTab.tabBarIndex)

            let addButton = makeAddButton(context: context)
            controller.addButton = addButton
            controller.view.addSubview(addButton)
        }

        return controller
    }

    func updateUIViewController(_ controller: PocketLedgerTabBarController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.onAddAction = onAddAction
        controller.tabBar.tintColor = UIColor(PocketLedgerTheme.accent)

        if #available(iOS 26, *),
           let addButton = controller.view.subviews.first(where: {
               ($0 as? UIButton)?.accessibilityIdentifier == "add-transaction-button"
           }) as? UIButton {
            addButton.menu = makeAddMenu(coordinator: context.coordinator)
        }

        let selectedIndex = selectedTab.tabBarIndex
        if controller.selectedIndex != selectedIndex {
            controller.selectedIndex = selectedIndex
        }
        if #available(iOS 26, *) {
            controller.selectVisibleTab(at: selectedIndex)
        }
    }

    private func makeViewControllers() -> [UIViewController] {
        let addExpense = onAddAction

        return AppTab.tabBarOrder.map { tab in
            let viewController: UIViewController
            switch tab {
            case .overview:
                viewController = UIHostingController(
                    rootView: DashboardView(
                        store: store,
                        onAddExpense: { addExpense(.expense) }
                    )
                )
            case .accounts:
                viewController = UIHostingController(
                    rootView: NavigationStack {
                        AccountsView(store: store)
                    }
                )
            case .transactions:
                viewController = UIHostingController(
                    rootView: NavigationStack {
                        TransactionsView(
                            store: store,
                            onAddExpense: { addExpense(.expense) }
                        )
                    }
                )
            case .metrics:
                viewController = UIHostingController(rootView: MetricsView(store: store))
            case .more:
                viewController = UIHostingController(
                    rootView: MoreView(
                        store: store,
                        security: security,
                        onAddExpense: { addExpense(.expense) }
                    )
                )
            }

            viewController.tabBarItem = UITabBarItem(
                title: tab.title,
                image: UIImage(systemName: tab.systemImage),
                tag: tab.tabBarIndex
            )
            viewController.tabBarItem.accessibilityIdentifier = "tab-\(tab.rawValue)"
            return viewController
        }
    }

    private func makeVisibleTabBarItems() -> [UITabBarItem] {
        AppTab.tabBarOrder.map { tab in
            let item = UITabBarItem(
                title: tab.title,
                image: UIImage(systemName: tab.systemImage),
                tag: tab.tabBarIndex
            )
            item.accessibilityIdentifier = "tab-\(tab.rawValue)"
            return item
        }
    }

    private func makeAddButton(context: Context) -> UIButton {
        var configuration = UIButton.Configuration.glass()
        configuration.image = UIImage(systemName: "plus")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 22,
            weight: .semibold
        )
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = UIColor(PocketLedgerTheme.accent.opacity(0.12))
        configuration.baseForegroundColor = UIColor(PocketLedgerTheme.accent)

        let button = UIButton(configuration: configuration)
        let coordinator = context.coordinator
        button.addAction(UIAction { [weak coordinator] _ in
            coordinator?.onAddAction(.expense)
        }, for: .primaryActionTriggered)
        button.tintColor = UIColor(PocketLedgerTheme.accent)
        button.menu = makeAddMenu(coordinator: context.coordinator)
        button.showsMenuAsPrimaryAction = false
        button.accessibilityIdentifier = "add-transaction-button"
        button.accessibilityLabel = "Add"
        button.accessibilityHint = "Choose what to add"
        return button
    }

    private func makeAddMenu(coordinator: Coordinator) -> UIMenu {
        let quickActions = UIMenu(
            title: "Quick add",
            options: .displayInline,
            children: [
                makeAction("Expense", image: "arrow.up.right", action: .expense, coordinator: coordinator),
                makeAction("Income", image: "arrow.down.left", action: .income, coordinator: coordinator),
                makeAction("Transfer", image: "arrow.left.arrow.right", action: .transfer, coordinator: coordinator)
            ]
        )

        let otherActions = UIMenu(
            title: "Other",
            options: .displayInline,
            children: [
                makeAction("Scan bill", image: "doc.text.viewfinder", action: .scanBill, coordinator: coordinator),
                makeAction("Scheduled", image: "calendar.badge.clock", action: .scheduled, coordinator: coordinator)
            ]
        )

        var menus: [UIMenuElement] = [quickActions, otherActions]
        let templates: [UIMenuElement] = store.data.templates.prefix(3).map { template in
            makeAction(
                template.name,
                image: "rectangle.stack",
                action: .template(template.id),
                coordinator: coordinator
            )
        }
        if !templates.isEmpty {
            menus.append(UIMenu(title: "Templates", options: .displayInline, children: templates))
        }

        let recent: [UIMenuElement] = store.recentTransactions.prefix(3).map { transaction in
            makeAction(
                transaction.note,
                image: "clock.arrow.circlepath",
                action: .recent(transaction.id),
                coordinator: coordinator
            )
        }
        if !recent.isEmpty {
            menus.append(UIMenu(title: "Recent", options: .displayInline, children: recent))
        }

        return UIMenu(title: "Add", children: menus)
    }

    private func makeAction(
        _ title: String,
        image: String,
        action: AddAction,
        coordinator: Coordinator
    ) -> UIAction {
        UIAction(title: title, image: UIImage(systemName: image)) { [weak coordinator] _ in
            coordinator?.onAddAction(action)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITabBarControllerDelegate, UITabBarDelegate {
        var parent: NativeTabBarController
        var onAddAction: (AddAction) -> Void

        init(parent: NativeTabBarController) {
            self.parent = parent
            self.onAddAction = parent.onAddAction
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            guard let index = tabBarController.viewControllers?.firstIndex(of: viewController),
                  index < AppTab.tabBarOrder.count else {
                return
            }

            let tab = AppTab.tabBarOrder[index]
            if parent.selectedTab != tab {
                parent.selectedTab = tab
            }
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard let index = tabBar.items?.firstIndex(of: item),
                  index < AppTab.tabBarOrder.count else {
                return
            }

            let tab = AppTab.tabBarOrder[index]
            if parent.selectedTab != tab {
                parent.selectedTab = tab
            }
        }
    }
}

private enum AddAction: Identifiable {
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

enum AppTab: String, Hashable {
    case overview
    case accounts
    case transactions
    case metrics
    case more

    static let tabBarOrder: [AppTab] = [.overview, .accounts, .metrics, .more]

    var tabBarIndex: Int {
        Self.tabBarOrder.firstIndex(of: self)
            ?? Self.tabBarOrder.firstIndex(of: .more)
            ?? 0
    }

    var title: String {
        switch self {
        case .overview:
            return "Overview"
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
            return "chart.bar.xaxis"
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

    var body: some View {
        NavigationStack {
            List {
                Section("History") {
                    NavigationLink {
                        TransactionsView(store: store, onAddExpense: onAddExpense)
                    } label: {
                        Label("Transactions", systemImage: "list.bullet.rectangle")
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
            .pocketScreen()
            .sheet(isPresented: $isShowingSetup) {
                SetupWizardView(store: store)
            }
        }
    }
}

@MainActor
private struct DashboardView: View {
    @ObservedObject var store: LedgerStore
    let onAddExpense: () -> Void
    @State private var editingTransaction: LedgerTransaction?
    @AppStorage(PocketLedgerTheme.colorThemeKey) private var selectedColorTheme = PocketLedgerColorTheme.ocean.rawValue
    @AppStorage(PocketLedgerTheme.appearanceModeKey) private var selectedAppearanceMode = PocketLedgerAppearanceMode.system.rawValue

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                PocketGlassContainer(spacing: 14) {
                    VStack(alignment: .leading, spacing: 16) {
                        dashboardHeader
                        balanceHero
                        monthSnapshot
                        recentActivity
                        upcomingSchedules
                        budgetSnapshot
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
            }
            .pocketScreen()
            .accessibilityIdentifier("dashboard-\(selectedColorTheme)")
            .preferredColorScheme(
                PocketLedgerAppearanceMode(rawValue: selectedAppearanceMode)?.preferredColorScheme
            )
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editingTransaction) { transaction in
                TransactionEditor(store: store, transaction: transaction)
            }
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pocket Ledger")
                    .font(.largeTitle.weight(.bold))
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
        .pocketGlassSurface(cornerRadius: 22, tint: PocketLedgerTheme.accent.opacity(0.08))
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

            Text(store.availableBalance(for: currency).formatted)
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
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
            .pocketGlassSurface(cornerRadius: 17)
        }
    }

    @ViewBuilder
    private var upcomingSchedules: some View {
        let schedules = store.data.scheduledTransactions
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                if lhs.nextRunDate != rhs.nextRunDate {
                    return lhs.nextRunDate < rhs.nextRunDate
                }
                return lhs.note.localizedCaseInsensitiveCompare(rhs.note) == .orderedAscending
            }

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
                .pocketGlassSurface(cornerRadius: 17)

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
                Text(schedule.nextRunDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2)
                    .foregroundStyle(PocketLedgerTheme.textTertiary)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(schedule.note.isEmpty ? schedule.kind.displayName : schedule.note), \(store.transactionSummary(schedule.transactionTemplate)), \(upcomingDateLabel(schedule.nextRunDate))"
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
        .pocketGlassSurface(cornerRadius: 17)
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
                NavigationLink("See all") {
                    TransactionsView(store: store, onAddExpense: onAddExpense)
                }
                .font(.caption.weight(.semibold))
            }

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
                    Button("Add expense", systemImage: "plus", action: onAddExpense)
                        .buttonStyle(.glassProminent)
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
                            onEdit: { editingTransaction = transaction },
                            onDuplicate: {},
                            onDelete: {},
                            onSaveTemplate: {},
                            allowsActions: false
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
                .pocketGlassSurface(cornerRadius: 17)
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

private enum TransactionPeriod: String, CaseIterable, Identifiable, Hashable {
    case all = "All time"
    case thisMonth = "This month"
    case lastMonth = "Last month"
    case thisYear = "This year"

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
    let onAddExpense: () -> Void
    @State private var selectedFilter: TransactionFilter = .all
    @State private var selectedPeriod: TransactionPeriod = .all
    @State private var searchText = ""
    @State private var transactionPage = 0
    @State private var editingTransaction: LedgerTransaction?
    @State private var transactionToDelete: LedgerTransaction?
    @State private var transactionToTemplate: LedgerTransaction?
    @State private var isPresentingBillScanner = false

    private let transactionsPerPage = 25

    var body: some View {
        ScrollView(showsIndicators: false) {
            PocketGlassContainer(spacing: 14) {
                VStack(alignment: .leading, spacing: 18) {
                    screenHeader

                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(TransactionFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Date range", selection: $selectedPeriod) {
                        ForEach(TransactionPeriod.allCases) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TextField("Search transactions, categories, or accounts", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)

                    transactionsSummary

                    if filteredTransactions.isEmpty {
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
                        Button("Add expense", systemImage: "plus", action: onAddExpense)
                            .buttonStyle(.glassProminent)
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
                                .pocketGlassSurface(cornerRadius: 18)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(PocketLedgerTheme.divider, lineWidth: 1)
                                }
                            }
                        }

                        transactionPagination
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .pocketScreen()
        .onChange(of: selectedFilter) { _, _ in
            transactionPage = 0
        }
        .onChange(of: selectedPeriod) { _, _ in
            transactionPage = 0
        }
        .onChange(of: searchText) { _, _ in
            transactionPage = 0
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

    private var screenHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Transactions")
                    .font(.largeTitle.weight(.bold))
                Text("Every inflow and outflow, in one place")
                    .font(.subheadline)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
            }

            Spacer()

            Button {
                isPresentingBillScanner = true
            } label: {
                Image(systemName: "doc.viewfinder")
                    .font(.body.weight(.bold))
                    .foregroundStyle(PocketLedgerTheme.positive)
                    .frame(minWidth: 44, minHeight: 44)
                    .pocketGlassSurface(
                        cornerRadius: 22,
                        tint: PocketLedgerTheme.positive.opacity(0.18),
                        interactive: true
                    )
            }
            .accessibilityLabel("Scan bill")

        }
    }

    private var filteredTransactions: [LedgerTransaction] {
        store.recentTransactions.filter { transaction in
            let matchesKind = selectedFilter.kind.map { transaction.kind == $0 } ?? true
            guard matchesKind else { return false }
            guard selectedPeriod.includes(transaction.date) else { return false }
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
        let grouped = Dictionary(grouping: pageTransactions) {
            Calendar.current.startOfDay(for: $0.date)
        }

        return grouped.keys.sorted(by: >).map { date in
            TransactionDay(date: date, transactions: grouped[date] ?? [])
        }
    }

    private var pageCount: Int {
        max(1, (filteredTransactions.count + transactionsPerPage - 1) / transactionsPerPage)
    }

    private var displayedPage: Int {
        min(transactionPage, pageCount - 1)
    }

    private var pageTransactions: [LedgerTransaction] {
        let pageStart = displayedPage * transactionsPerPage
        return Array(filteredTransactions.dropFirst(pageStart).prefix(transactionsPerPage))
    }

    @ViewBuilder
    private var transactionPagination: some View {
        if pageCount > 1 {
            HStack(spacing: 16) {
                Button {
                    transactionPage = max(0, displayedPage - 1)
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .disabled(displayedPage == 0)

                Text("Page \(displayedPage + 1) of \(pageCount)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(PocketLedgerTheme.textSecondary)

                Button {
                    transactionPage = min(pageCount - 1, displayedPage + 1)
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(displayedPage == pageCount - 1)
            }
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    private var transactionsSummary: some View {
        let expenses = filteredExpenseTotals

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

    private var filteredExpenseTotals: [LedgerCurrency: Int64] {
        var totals: [LedgerCurrency: Int64] = [:]
        for transaction in filteredTransactions where transaction.kind == .expense {
            for currency in LedgerCurrency.allCases {
                totals[currency, default: 0] += financeNetExpenseAmount(
                    transaction,
                    currency: currency,
                    in: store.data
                )
            }
        }
        return totals
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
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onSaveTemplate: () -> Void
    let allowsActions: Bool

    var body: some View {
        Button(action: onEdit) {
            rowContent
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(transaction.note), \(rowSubtitle), \(amountText)")
        .accessibilityHint("Opens transaction details")
        .contextMenu {
            if allowsActions {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
                Button("Save as template", systemImage: "rectangle.stack.badge.plus", action: onSaveTemplate)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if allowsActions {
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                Button("Edit", systemImage: "pencil", action: onEdit)
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
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
    @State private var editingAccount: Account?

    var body: some View {
        ScrollView(showsIndicators: false) {
            PocketGlassContainer(spacing: 14) {
                VStack(alignment: .leading, spacing: 18) {
                    screenHeader
                    globalPositionSummary

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
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .pocketScreen()
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.inline)
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

    private var screenHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Accounts")
                    .font(.largeTitle.weight(.bold))
                Text("Tap an account for activity; hold it to edit, archive, or reorder")
                    .font(.subheadline)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
            }

            Spacer()

            Button {
                presentAccount(nil)
            } label: {
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
            .accessibilityLabel("Add account")
        }
    }

    private func accountSection(type: AccountType, accounts: [Account]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: type.systemImage)
                        .foregroundStyle(PocketLedgerTheme.accent)
                    Text(type.displayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                    Text("\(accounts.count) \(accounts.count == 1 ? "account" : "accounts")")
                        .font(.caption)
                        .foregroundStyle(PocketLedgerTheme.textTertiary)
                }

                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(accounts) { account in
                    let accountPosition = accounts.firstIndex(where: { $0.id == account.id }) ?? 0
                    NavigationLink {
                        AccountDetailView(store: store, accountID: account.id)
                    } label: {
                        AccountRow(account: account, balance: store.balance(for: account))
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") {
                                    presentAccount(account)
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
                                    _ = store.setAccountArchived(
                                        accountID: account.id,
                                        isArchived: true
                                    )
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Edit", systemImage: "pencil") {
                            presentAccount(account)
                        }
                        Button("Archive", systemImage: "archivebox") {
                            _ = store.setAccountArchived(
                                accountID: account.id,
                                isArchived: true
                            )
                        }
                        .tint(PocketLedgerTheme.warning)
                    }
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

    private var archivedAccounts: [Account] {
        store.data.accounts.filter(\.isArchived)
    }

    private var archivedAccountsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Archived")
                .font(.title3.weight(.bold))

            VStack(spacing: 0) {
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
                    .padding(.vertical, 10)

                    Divider().overlay(PocketLedgerTheme.divider)
                }
            }
            .padding(.horizontal, 14)
            .pocketGlassSurface(cornerRadius: 18)
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(PocketLedgerTheme.divider, lineWidth: 1)
            }

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
                    screenHeader

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
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingCategory, onDismiss: { editingCategory = nil }) {
            CategoryEditor(store: store, category: editingCategory)
        }
    }

    private var screenHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Categories")
                    .font(.largeTitle.weight(.bold))
                Text("Make every expense easy to understand")
                    .font(.subheadline)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
            }

            Spacer()

            Button {
                presentCategory(nil)
            } label: {
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
            .accessibilityLabel("Add category")
        }
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
        .pocketGlassSurface(cornerRadius: 13, tint: PocketLedgerTheme.surfaceElevated.opacity(0.22))
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onEdit)
            Button("Archive", systemImage: "archivebox", action: onArchive)
        }
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
                    TextField("Amount", text: $openingBalance)
                        .keyboardType(.decimalPad)
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
            HStack {
                Picker("Account", selection: $line.accountID) {
                    ForEach(store.data.accounts.filter { account in
                        !account.isArchived || (allowsArchivedAccount && account.id == line.accountID)
                    }) { account in
                        Text("\(account.name) (\(account.currency.rawValue))")
                            .tag(account.id)
                    }
                }

                Button("New account", systemImage: "plus.circle", action: onCreateAccount)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("New account")
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
    private let editingScheduleID: UUID?
    private let editingScheduleLastRunDate: Date?
    private let editingScheduleNextRunDate: Date?
    private let editingScheduleFrequency: ScheduleFrequency?
    private let editingScheduleRecurrenceDay: Int?
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
            ?? scheduledTransaction?.amountDue?.currency
            ?? initialBillTotal?.currency
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
            (sourceTransaction?.outflows ?? scheduledTransaction?.outflows ?? []).contains { $0.money.currency == currency }
                || (sourceTransaction?.inflows ?? scheduledTransaction?.inflows ?? []).contains { $0.money.currency == currency }
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
            } ?? (resolvedInitialKind == .transfer
                ? [MovementDraft(accountID: initialDestinationAccountID, amount: "")]
                : [])
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

                timingSection
                detailsSection
                attachmentSection

                outgoingMovementSection
                receivingMovementSection
                exchangeRateSection
            }
            .onAppear {
                if kind == .transfer && inflows.isEmpty {
                    inflows.append(newReceivingMovementDraft)
                }
                synchronizeRatePair()
                synchronizeAutomaticTransferAmount()
            }
            .onChange(of: kind) { _, newKind in
                if newKind == .transfer && inflows.isEmpty {
                    inflows.append(newReceivingMovementDraft)
                }
                if newKind != .transfer {
                    automaticTransferDestinationAmount = nil
                }
                synchronizeRatePair()
                synchronizeAutomaticTransferAmount()
            }
            .onChange(of: selectedCurrencies) { _, _ in
                synchronizeRatePair()
                synchronizeAutomaticTransferAmount()
            }
            .onChange(of: outflows) { _, _ in
                synchronizeAutomaticTransferAmount()
            }
            .onChange(of: inflows) { oldInflows, newInflows in
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
                DatePicker("First run", selection: $date, displayedComponents: .date)

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

    @ViewBuilder
    private var detailsSection: some View {
        Section("Details") {
            TextField("What was this for?", text: $note)

            if kind == .expense {
                HStack {
                    if selectableCategories.isEmpty {
                        Text("No categories yet — this expense will be Uncategorized.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Category", selection: $categoryID) {
                            Text("Uncategorized").tag(UUID?.none)
                            ForEach(selectableCategories) { category in
                                Text(store.categoryPath(for: category.id))
                                    .tag(Optional(category.id))
                            }
                        }
                    }

                    Button("New category", systemImage: "plus.circle") {
                        isShowingNewCategory = true
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("New category")
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
           let category = store.data.categories.first(where: { $0.id == categoryID }),
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
        MovementDraft(accountID: store.activeAccounts.first?.id ?? UUID(), amount: "")
    }

    private var newReceivingMovementDraft: MovementDraft {
        let sourceAccountIDs = Set(outflows.map(\.accountID))
        let account = store.activeAccounts.first(where: { !sourceAccountIDs.contains($0.id) })
            ?? store.activeAccounts.first
        return MovementDraft(accountID: account?.id ?? UUID(), amount: "")
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

    private var rateCurrencyPair: (base: LedgerCurrency, quote: LedgerCurrency)? {
        guard let sourceCurrency = outflows.first.flatMap({ store.account(with: $0.accountID)?.currency }),
              let destinationCurrency = inflows.first.flatMap({ store.account(with: $0.accountID)?.currency }),
              sourceCurrency != destinationCurrency else {
            return nil
        }
        return (base: sourceCurrency, quote: destinationCurrency)
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

        let sourceUnits = parsedOutflows
            .filter { $0.money.currency == pair.base }
            .reduce(Decimal.zero) { total, movement in
                total + Decimal(movement.money.minorUnits) / Decimal(pair.base.minorUnitScale)
            }
        let destinationUnits = parsedInflows
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
              let sourceMoney = Money.parse(outflows[0].amount, currency: sourceAccount.currency),
              sourceMoney.minorUnits > 0 else {
            clearAutomaticTransferAmount()
            return
        }

        let destinationMoney: Money?
        if sourceAccount.currency == destinationAccount.currency {
            destinationMoney = sourceMoney
        } else {
            guard let rate = automaticTransferRate else {
                clearAutomaticTransferAmount()
                return
            }
            let sourceUnits = Decimal(sourceMoney.minorUnits) / Decimal(sourceMoney.currency.minorUnitScale)
            destinationMoney = Self.money(
                units: sourceUnits * rate,
                currency: destinationAccount.currency
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

        if kind == .transfer && selectedCurrencies.count > 1 {
            guard appliedExchangeRate != nil else {
                return false
            }
        } else if selectedCurrencies.count > 1 && useCustomRate {
            guard customExchangeRate != nil else {
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
        if kind == .transfer && selectedCurrencies.count > 1 {
            guard let appliedExchangeRate else {
                errorMessage = "Enter both transfer amounts or set a positive rate override."
                return
            }
            exchangeRate = appliedExchangeRate
        } else if selectedCurrencies.count > 1 && useCustomRate {
            guard let customExchangeRate else {
                errorMessage = "Enter a positive custom exchange rate with different currencies."
                return
            }
            exchangeRate = customExchangeRate
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
        dismiss()
    }

    private func deleteAttachment(_ attachment: LedgerAttachment) {
        guard store.deleteAttachment(id: attachment.id) else { return }
        attachmentIDs.removeAll { $0 == attachment.id }
    }
}
