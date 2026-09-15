import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var store = LedgerStore()
    @StateObject private var security = AppSecurityService()
    @State private var isPresentingTransaction = false
    @State private var isUnlocked = false
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
            } else if phase == .inactive || phase == .background {
                isPresentingTransaction = false
                if security.isPasscodeEnabled {
                    isUnlocked = false
                }
            }
        }
        .onChange(of: security.isPasscodeEnabled) { _, enabled in
            isUnlocked = !enabled
        }
    }

    private var unlockedContent: some View {
        TabView {
            DashboardView(store: store, onAddTransaction: presentTransaction)
                .tabItem {
                    Label("Overview", systemImage: "chart.bar.xaxis")
                }

            TransactionsView(store: store, onAddTransaction: presentTransaction)
                .tabItem {
                    Label("Transactions", systemImage: "list.bullet.rectangle")
                }

            AccountsView(store: store)
                .tabItem {
                    Label("Accounts", systemImage: "wallet.pass")
                }

            CategoriesView(store: store)
                .tabItem {
                    Label("Categories", systemImage: "square.grid.2x2")
                }

            SecuritySettingsView(security: security)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(.indigo)
        .sheet(isPresented: $isPresentingTransaction) {
            TransactionEditor(store: store)
        }
    }

    private func presentTransaction() {
        isPresentingTransaction = true
    }
}

@MainActor
private struct DashboardView: View {
    @ObservedObject var store: LedgerStore
    let onAddTransaction: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    balanceCard
                    metricsCard
                    accountsCard
                    recentTransactionsCard

                    if let status = store.lastActionStatus {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Overview")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onAddTransaction) {
                        Label("Add transaction", systemImage: "plus")
                    }
                }
            }
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Available across cash and banks", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            ForEach(LedgerCurrency.allCases) { currency in
                HStack {
                    Text(currency.rawValue)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(store.availableBalance(for: currency).formatted)
                        .font(.title3.weight(.bold).monospacedDigit())
                }
            }

            Text("Loans are tracked separately on the Accounts tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardSurface()
    }

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("This month", systemImage: "calendar")
                .font(.headline)

            HStack(spacing: 10) {
                metricTile(
                    title: "Transactions",
                    value: "\(store.monthTransactionCount)",
                    systemImage: "arrow.left.arrow.right"
                )
                metricTile(
                    title: "Top category",
                    value: store.topCategoryThisMonth ?? "—",
                    systemImage: "tag"
                )
            }

            ForEach(LedgerCurrency.allCases) { currency in
                let total = store.monthlyExpenseTotals()[currency] ?? 0
                HStack {
                    Text("Expenses in \(currency.rawValue)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Money(currency: currency, minorUnits: total).formatted)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
            }
        }
        .cardSurface()
    }

    private func metricTile(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.indigo)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var accountsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Accounts", systemImage: "wallet.pass")
                .font(.headline)

            ForEach(Array(store.data.accounts.prefix(4))) { account in
                AccountRow(account: account, balance: store.balance(for: account))
            }

            if store.data.accounts.count > 4 {
                Text("See all accounts in the Accounts tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardSurface()
    }

    private var recentTransactionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recent transactions", systemImage: "clock")
                .font(.headline)

            if store.recentTransactions.isEmpty {
                Text("Your first transaction can use more than one currency and more than one account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.recentTransactions.prefix(5))) { transaction in
                    TransactionRow(transaction: transaction, store: store)
                }
            }
        }
        .cardSurface()
    }
}

@MainActor
private struct TransactionsView: View {
    @ObservedObject var store: LedgerStore
    let onAddTransaction: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if store.recentTransactions.isEmpty {
                    Text("No transactions yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.recentTransactions) { transaction in
                        TransactionRow(transaction: transaction, store: store)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onAddTransaction) {
                        Label("Add transaction", systemImage: "plus")
                    }
                }
            }
        }
    }
}

@MainActor
private struct TransactionRow: View {
    let transaction: LedgerTransaction
    @ObservedObject var store: LedgerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.note)
                        .font(.body.weight(.medium))
                    Text(rowSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Text(store.transactionSummary(transaction))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .multilineTextAlignment(.trailing)
            }

            if let amountDue = transaction.amountDue {
                Text("Bill total: \(amountDue.formatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let exchangeRate = transaction.exchangeRate {
                Text(exchangeRate.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let shortfall = transaction.changeAdjustment?.shortfall {
                Text(shortfall.minorUnits > 0
                     ? "Change adjusted: \(shortfall.formatted) short"
                     : "Change adjusted by \(shortfall.formatted)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
    }

    private var rowSubtitle: String {
        let category = store.categoryPath(for: transaction.categoryID)
        return "\(transaction.kind.displayName) · \(category) · \(transaction.date.formatted(date: .abbreviated, time: .shortened))"
    }
}

@MainActor
private struct AccountsView: View {
    @ObservedObject var store: LedgerStore
    @State private var isPresentingAccount = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(LedgerCurrency.allCases) { currency in
                    let accounts = store.data.accounts.filter { $0.currency == currency }
                    if !accounts.isEmpty {
                        Section(currency.rawValue) {
                            ForEach(accounts) { account in
                                AccountRow(account: account, balance: store.balance(for: account))
                            }
                        }
                    }
                }

                Section {
                    Text(store.storageAvailable
                         ? "Stored locally in the shared app container."
                         : "Shared storage is unavailable; changes last for this session only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingAccount = true
                    } label: {
                        Label("Add account", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingAccount) {
                AccountEditor(store: store)
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
            Image(systemName: account.type.systemImage)
                .foregroundStyle(.indigo)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                Text(account.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(balance.formatted)
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }
}

@MainActor
private struct CategoriesView: View {
    @ObservedObject var store: LedgerStore
    @State private var isPresentingCategory = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.rootCategories) { parent in
                    Section {
                        CategoryRow(category: parent)

                        ForEach(store.data.categories.filter { $0.parentID == parent.id }) { child in
                            CategoryRow(category: child, isChild: true)
                        }
                    } header: {
                        Text(parent.name)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingCategory = true
                    } label: {
                        Label("Add category", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingCategory) {
                CategoryEditor(store: store)
            }
        }
    }
}

@MainActor
private struct CategoryRow: View {
    let category: LedgerCategory
    var isChild = false

    var body: some View {
        Label(category.name, systemImage: category.systemImage)
            .padding(.leading, isChild ? 20 : 0)
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
                }

                Section("Opening balance") {
                    TextField("Amount", text: $openingBalance)
                    Text("The amount is stored in the account's own currency.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New account")
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
                openingBalance: balance
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
            .navigationTitle("New category")
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
private struct TransactionEditor: View {
    @ObservedObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var kind: TransactionKind = .expense
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

    init(store: LedgerStore) {
        _store = ObservedObject(wrappedValue: store)
        let firstAccountID = store.data.accounts.first?.id ?? UUID()
        _outflows = State(initialValue: [MovementDraft(accountID: firstAccountID, amount: "")])
        _categoryID = State(
            initialValue: store.data.categories.first(where: { $0.parentID != nil })?.id
                ?? store.data.categories.first?.id
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("What was this for?", text: $note)
                    Picker("Type", selection: $kind) {
                        ForEach(TransactionKind.allCases) { transactionKind in
                            Text(transactionKind.displayName).tag(transactionKind)
                        }
                    }

                    if kind == .expense {
                        Picker("Category", selection: $categoryID) {
                            ForEach(store.data.categories) { category in
                                Text(store.categoryPath(for: category.id))
                                    .tag(Optional(category.id))
                            }
                        }
                        Picker("Bill currency", selection: $dueCurrency) {
                            ForEach(LedgerCurrency.allCases) { currency in
                                Text(currency.rawValue).tag(currency)
                            }
                        }
                        TextField("Bill total (optional)", text: $amountDue)
                    }
                }

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

                Section {
                    if inflows.isEmpty {
                        Button {
                            inflows.append(newMovementDraft)
                        } label: {
                            Label("Add returned money", systemImage: "arrow.down.circle")
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
                            if let preview = shortfallPreview {
                                Text(preview)
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } header: {
                    Text(kind == .expense ? "Change / money returned" : "Money entering accounts")
                } footer: {
                    Text("Returned money may go to a different account and currency than the payment.")
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
                            Text("Example: 1 USD = 100000 LBP.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("New transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
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

    private var newMovementDraft: MovementDraft {
        MovementDraft(accountID: store.data.accounts.first?.id ?? UUID(), amount: "")
    }

    private var selectedCurrencies: [LedgerCurrency] {
        let accountIDs = outflows.map(\.accountID) + inflows.map(\.accountID)
        let currencies = Set(accountIDs.compactMap { store.account(with: $0)?.currency })
        return LedgerCurrency.allCases.filter { currencies.contains($0) }
    }

    private var parsedOutflows: [MoneyMovement]? {
        parseMovements(outflows)
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
            guard !parsedOutflows.isEmpty, categoryID != nil else { return false }
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

        store.addTransaction(
            LedgerTransaction(
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? kind.displayName
                    : note.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: kind,
                categoryID: kind == .expense ? categoryID : nil,
                amountDue: parsedAmountDue,
                outflows: parsedOutflows,
                inflows: parsedInflows,
                exchangeRate: exchangeRate,
                changeAdjustment: changeAdjustment
            )
        )
        dismiss()
    }
}

private extension View {
    func cardSurface() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}
