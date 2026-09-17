import Foundation

enum LedgerCurrency: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case usd = "USD"
    case lbp = "LBP"
    case eur = "EUR"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usd:
            return "US Dollar"
        case .lbp:
            return "Lebanese Pound"
        case .eur:
            return "Euro"
        }
    }

    var fractionDigits: Int {
        switch self {
        case .usd:
            return 2
        case .lbp:
            return 0
        case .eur:
            return 2
        }
    }

    var minorUnitScale: Int64 {
        switch self {
        case .usd:
            return 100
        case .lbp:
            return 1
        case .eur:
            return 100
        }
    }

    func formatted(minorUnits: Int64) -> String {
        let isNegative = minorUnits < 0
        let absoluteMinorUnits = Swift.abs(minorUnits)
        let amount = Decimal(absoluteMinorUnits) / Decimal(minorUnitScale)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        let number = formatter.string(from: NSDecimalNumber(decimal: amount)) ?? String(describing: amount)
        let sign = isNegative ? "-" : ""

        switch self {
        case .usd:
            return "\(sign)$\(number)"
        case .lbp:
            return "\(sign)LBP \(number)"
        case .eur:
            return "\(sign)€\(number)"
        }
    }
}

struct Money: Codable, Equatable, Sendable {
    let currency: LedgerCurrency
    let minorUnits: Int64

    var formatted: String {
        currency.formatted(minorUnits: minorUnits)
    }

    static func parse(_ rawValue: String, currency: LedgerCurrency) -> Money? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")

        guard !normalized.isEmpty,
              let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }

        let scaled = decimal * Decimal(currency.minorUnitScale)
        var rounded = Decimal()
        var value = scaled
        NSDecimalRound(&rounded, &value, 0, .plain)
        return Money(
            currency: currency,
            minorUnits: NSDecimalNumber(decimal: rounded).int64Value
        )
    }
}

enum AccountType: String, Codable, CaseIterable, Identifiable, Hashable {
    case cash
    case bankAccount
    case loan
    case physicalAsset
    case investment

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cash:
            return "Cash"
        case .bankAccount:
            return "Bank account"
        case .loan:
            return "Loan"
        case .physicalAsset:
            return "Physical asset"
        case .investment:
            return "Investment"
        }
    }

    var systemImage: String {
        switch self {
        case .cash:
            return "banknote"
        case .bankAccount:
            return "building.columns"
        case .loan:
            return "arrow.triangle.2.circlepath"
        case .physicalAsset:
            return "diamond.fill"
        case .investment:
            return "chart.line.uptrend.xyaxis"
        }
    }
}

struct Account: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var type: AccountType
    var currency: LedgerCurrency
    var openingBalance: Money
    var includeInTotals: Bool
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        name: String,
        type: AccountType,
        currency: LedgerCurrency,
        openingBalance: Money,
        includeInTotals: Bool = true,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.currency = currency
        self.openingBalance = openingBalance
        self.includeInTotals = includeInTotals
        self.isArchived = isArchived
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case currency
        case openingBalance
        case includeInTotals
        case isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(AccountType.self, forKey: .type)
        currency = try container.decode(LedgerCurrency.self, forKey: .currency)
        openingBalance = try container.decode(Money.self, forKey: .openingBalance)
        includeInTotals = try container.decodeIfPresent(Bool.self, forKey: .includeInTotals) ?? true
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(currency, forKey: .currency)
        try container.encode(openingBalance, forKey: .openingBalance)
        try container.encode(includeInTotals, forKey: .includeInTotals)
        try container.encode(isArchived, forKey: .isArchived)
    }
}

enum TransactionKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case expense
    case income
    case transfer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .expense:
            return "Expense"
        case .income:
            return "Income"
        case .transfer:
            return "Transfer"
        }
    }
}

enum ScheduleFrequency: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case once
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .once:
            return "Once"
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .yearly:
            return "Yearly"
        }
    }

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .once:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}

enum TransactionTiming: String, CaseIterable, Identifiable, Hashable, Sendable {
    case now
    case scheduled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .now:
            return "Now"
        case .scheduled:
            return "Schedule"
        }
    }
}

struct MoneyMovement: Identifiable, Codable, Equatable {
    let id: UUID
    var accountID: UUID
    var money: Money

    init(id: UUID = UUID(), accountID: UUID, money: Money) {
        self.id = id
        self.accountID = accountID
        self.money = money
    }
}

struct ExchangeRate: Codable, Equatable, Identifiable {
    var baseCurrency: LedgerCurrency
    var quoteCurrency: LedgerCurrency
    var quoteUnitsPerBaseUnit: Decimal

    var id: String {
        "\(baseCurrency.rawValue)-\(quoteCurrency.rawValue)"
    }

    var summary: String {
        let number = NSDecimalNumber(decimal: quoteUnitsPerBaseUnit).stringValue
        return "1 \(baseCurrency.rawValue) = \(number) \(quoteCurrency.rawValue)"
    }
}

struct ChangeAdjustment: Codable, Equatable {
    var requested: Money
    var actual: Money

    var shortfall: Money? {
        guard requested.currency == actual.currency else { return nil }
        let difference = requested.minorUnits - actual.minorUnits
        guard difference != 0 else { return nil }
        return Money(currency: requested.currency, minorUnits: difference)
    }
}

struct LedgerCategory: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var parentID: UUID?
    var systemImage: String
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        systemImage: String = "tag",
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.systemImage = systemImage
        self.isArchived = isArchived
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case parentID
        case systemImage
        case isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        parentID = try container.decodeIfPresent(UUID.self, forKey: .parentID)
        systemImage = try container.decodeIfPresent(String.self, forKey: .systemImage) ?? "tag"
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(parentID, forKey: .parentID)
        try container.encode(systemImage, forKey: .systemImage)
        try container.encode(isArchived, forKey: .isArchived)
    }
}

struct LedgerTransaction: Identifiable, Codable, Equatable {
    let id: UUID
    var date: Date
    var note: String
    var kind: TransactionKind
    var categoryID: UUID?
    var amountDue: Money?
    var outflows: [MoneyMovement]
    var inflows: [MoneyMovement]
    var exchangeRate: ExchangeRate?
    var changeAdjustment: ChangeAdjustment?
    var attachmentIDs: [UUID]

    init(
        id: UUID = UUID(),
        date: Date = .now,
        note: String,
        kind: TransactionKind,
        categoryID: UUID?,
        amountDue: Money? = nil,
        outflows: [MoneyMovement],
        inflows: [MoneyMovement],
        exchangeRate: ExchangeRate? = nil,
        changeAdjustment: ChangeAdjustment? = nil,
        attachmentIDs: [UUID] = []
    ) {
        self.id = id
        self.date = date
        self.note = note
        self.kind = kind
        self.categoryID = categoryID
        self.amountDue = amountDue
        self.outflows = outflows
        self.inflows = inflows
        self.exchangeRate = exchangeRate
        self.changeAdjustment = changeAdjustment
        self.attachmentIDs = attachmentIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case note
        case kind
        case categoryID
        case amountDue
        case outflows
        case inflows
        case exchangeRate
        case changeAdjustment
        case attachmentIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        note = try container.decode(String.self, forKey: .note)
        kind = try container.decode(TransactionKind.self, forKey: .kind)
        categoryID = try container.decodeIfPresent(UUID.self, forKey: .categoryID)
        amountDue = try container.decodeIfPresent(Money.self, forKey: .amountDue)
        outflows = try container.decode([MoneyMovement].self, forKey: .outflows)
        inflows = try container.decode([MoneyMovement].self, forKey: .inflows)
        exchangeRate = try container.decodeIfPresent(ExchangeRate.self, forKey: .exchangeRate)
        changeAdjustment = try container.decodeIfPresent(ChangeAdjustment.self, forKey: .changeAdjustment)
        attachmentIDs = try container.decodeIfPresent([UUID].self, forKey: .attachmentIDs) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(note, forKey: .note)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(categoryID, forKey: .categoryID)
        try container.encodeIfPresent(amountDue, forKey: .amountDue)
        try container.encode(outflows, forKey: .outflows)
        try container.encode(inflows, forKey: .inflows)
        try container.encodeIfPresent(exchangeRate, forKey: .exchangeRate)
        try container.encodeIfPresent(changeAdjustment, forKey: .changeAdjustment)
        try container.encode(attachmentIDs, forKey: .attachmentIDs)
    }
}

struct ScheduledTransaction: Identifiable, Codable, Equatable {
    let id: UUID
    var nextRunDate: Date
    var frequency: ScheduleFrequency
    var isEnabled: Bool
    var lastRunDate: Date?
    var note: String
    var kind: TransactionKind
    var categoryID: UUID?
    var amountDue: Money?
    var outflows: [MoneyMovement]
    var inflows: [MoneyMovement]
    var exchangeRate: ExchangeRate?
    var changeAdjustment: ChangeAdjustment?

    init(
        id: UUID = UUID(),
        nextRunDate: Date,
        frequency: ScheduleFrequency,
        isEnabled: Bool = true,
        lastRunDate: Date? = nil,
        note: String,
        kind: TransactionKind,
        categoryID: UUID?,
        amountDue: Money? = nil,
        outflows: [MoneyMovement],
        inflows: [MoneyMovement],
        exchangeRate: ExchangeRate? = nil,
        changeAdjustment: ChangeAdjustment? = nil
    ) {
        self.id = id
        self.nextRunDate = nextRunDate
        self.frequency = frequency
        self.isEnabled = isEnabled
        self.lastRunDate = lastRunDate
        self.note = note
        self.kind = kind
        self.categoryID = categoryID
        self.amountDue = amountDue
        self.outflows = outflows
        self.inflows = inflows
        self.exchangeRate = exchangeRate
        self.changeAdjustment = changeAdjustment
    }

    var transactionTemplate: LedgerTransaction {
        LedgerTransaction(
            date: nextRunDate,
            note: note,
            kind: kind,
            categoryID: categoryID,
            amountDue: amountDue,
            outflows: outflows,
            inflows: inflows,
            exchangeRate: exchangeRate,
            changeAdjustment: changeAdjustment
        )
    }

    func materializedTransaction(on date: Date) -> LedgerTransaction {
        LedgerTransaction(
            date: date,
            note: note,
            kind: kind,
            categoryID: categoryID,
            amountDue: amountDue,
            outflows: outflows.map { MoneyMovement(accountID: $0.accountID, money: $0.money) },
            inflows: inflows.map { MoneyMovement(accountID: $0.accountID, money: $0.money) },
            exchangeRate: exchangeRate,
            changeAdjustment: changeAdjustment
        )
    }
}

struct FinanceWidgetSnapshot: Equatable, Sendable {
    let usdAvailable: Money
    let lbpAvailable: Money
    let eurAvailable: Money
    let latestTransactionDescription: String
    let lastUpdated: Date
    let appGroupAvailable: Bool

    var balanceSummary: String {
        [usdAvailable, lbpAvailable, eurAvailable]
            .map(\.formatted)
            .joined(separator: " · ")
    }
}

struct LedgerBudget: Identifiable, Codable, Equatable {
    let id: UUID
    var categoryID: UUID
    var currency: LedgerCurrency
    var monthlyLimit: Money
    var rollover: Bool
    var startedAt: Date?

    init(
        id: UUID = UUID(),
        categoryID: UUID,
        currency: LedgerCurrency,
        monthlyLimit: Money,
        rollover: Bool = false,
        startedAt: Date? = .now
    ) {
        self.id = id
        self.categoryID = categoryID
        self.currency = currency
        self.monthlyLimit = monthlyLimit
        self.rollover = rollover
        self.startedAt = startedAt
    }
}

func financeBudgetSpent(
    _ budget: LedgerBudget,
    in data: FinanceData,
    interval: DateInterval? = nil
) -> Money {
    let period = interval ?? (
        Calendar.current.dateInterval(of: .month, for: .now)
            ?? DateInterval(start: .distantPast, duration: .zero)
    )
    let spent = data.transactions
        .filter {
            $0.kind == .expense
                && period.contains($0.date)
                && $0.categoryID == budget.categoryID
        }
        .flatMap(\.outflows)
        .filter { movement in
            data.accounts.first(where: { $0.id == movement.accountID })?.includeInTotals == true
                && movement.money.currency == budget.currency
        }
        .reduce(Int64.zero) { $0 + $1.money.minorUnits }
    return Money(currency: budget.currency, minorUnits: spent)
}

func financeBudgetAllowance(
    _ budget: LedgerBudget,
    in data: FinanceData,
    interval: DateInterval? = nil
) -> Money {
    let currentMonth = interval ?? (
        Calendar.current.dateInterval(of: .month, for: .now)
            ?? DateInterval(start: .distantPast, duration: .zero)
    )
    guard budget.rollover else { return budget.monthlyLimit }

    let calendar = Calendar.current
    let startingMonth = calendar.dateInterval(
        of: .month,
        for: budget.startedAt ?? currentMonth.start
    )?.start ?? currentMonth.start
    var month = startingMonth
    var carry = Int64.zero

    while month < currentMonth.start {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else {
            break
        }
        let spent = financeBudgetSpent(budget, in: data, interval: monthInterval).minorUnits
        carry += max(budget.monthlyLimit.minorUnits - spent, 0)
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: month),
              nextMonth > month else {
            break
        }
        month = nextMonth
    }

    return Money(
        currency: budget.currency,
        minorUnits: budget.monthlyLimit.minorUnits + carry
    )
}

struct LedgerTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var note: String
    var kind: TransactionKind
    var categoryID: UUID?
    var amountDue: Money?
    var outflows: [MoneyMovement]
    var inflows: [MoneyMovement]
    var exchangeRate: ExchangeRate?
    var changeAdjustment: ChangeAdjustment?

    init(
        id: UUID = UUID(),
        name: String,
        note: String,
        kind: TransactionKind,
        categoryID: UUID?,
        amountDue: Money?,
        outflows: [MoneyMovement],
        inflows: [MoneyMovement],
        exchangeRate: ExchangeRate?,
        changeAdjustment: ChangeAdjustment?
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.kind = kind
        self.categoryID = categoryID
        self.amountDue = amountDue
        self.outflows = outflows
        self.inflows = inflows
        self.exchangeRate = exchangeRate
        self.changeAdjustment = changeAdjustment
    }

    init(name: String, transaction: LedgerTransaction) {
        self.init(
            name: name,
            note: transaction.note,
            kind: transaction.kind,
            categoryID: transaction.categoryID,
            amountDue: transaction.amountDue,
            outflows: transaction.outflows,
            inflows: transaction.inflows,
            exchangeRate: transaction.exchangeRate,
            changeAdjustment: transaction.changeAdjustment
        )
    }

    var transactionTemplate: LedgerTransaction {
        LedgerTransaction(
            note: note,
            kind: kind,
            categoryID: categoryID,
            amountDue: amountDue,
            outflows: outflows.map { MoneyMovement(accountID: $0.accountID, money: $0.money) },
            inflows: inflows.map { MoneyMovement(accountID: $0.accountID, money: $0.money) },
            exchangeRate: exchangeRate,
            changeAdjustment: changeAdjustment
        )
    }
}

struct LedgerReceiptLineItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var quantity: Int
    var unitPrice: Money?
    var lineTotal: Money?

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Int,
        unitPrice: Money?,
        lineTotal: Money?
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.lineTotal = lineTotal
    }
}

struct LedgerAttachment: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var fileName: String
    var contentType: String
    var relativePath: String
    var createdAt: Date
    var receiptItems: [LedgerReceiptLineItem]
    var extractedTotal: Money?

    init(
        id: UUID = UUID(),
        fileName: String,
        contentType: String,
        relativePath: String,
        createdAt: Date = .now,
        receiptItems: [LedgerReceiptLineItem] = [],
        extractedTotal: Money? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.contentType = contentType
        self.relativePath = relativePath
        self.createdAt = createdAt
        self.receiptItems = receiptItems
        self.extractedTotal = extractedTotal
    }
}

struct FinanceData: Codable, Equatable {
    var accounts: [Account]
    var categories: [LedgerCategory]
    var transactions: [LedgerTransaction]
    var scheduledTransactions: [ScheduledTransaction]
    var exchangeRates: [ExchangeRate]
    var budgets: [LedgerBudget]
    var templates: [LedgerTemplate]
    var attachments: [LedgerAttachment]

    init(
        accounts: [Account],
        categories: [LedgerCategory],
        transactions: [LedgerTransaction],
        scheduledTransactions: [ScheduledTransaction] = [],
        exchangeRates: [ExchangeRate] = [],
        budgets: [LedgerBudget] = [],
        templates: [LedgerTemplate] = [],
        attachments: [LedgerAttachment] = []
    ) {
        self.accounts = accounts
        self.categories = categories
        self.transactions = transactions
        self.scheduledTransactions = scheduledTransactions
        self.exchangeRates = exchangeRates
        self.budgets = budgets
        self.templates = templates
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case accounts
        case categories
        case transactions
        case scheduledTransactions
        case exchangeRates
        case budgets
        case templates
        case attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try container.decode([Account].self, forKey: .accounts)
        categories = try container.decode([LedgerCategory].self, forKey: .categories)
        transactions = try container.decode([LedgerTransaction].self, forKey: .transactions)
        scheduledTransactions = try container.decodeIfPresent(
            [ScheduledTransaction].self,
            forKey: .scheduledTransactions
        ) ?? []
        exchangeRates = try container.decodeIfPresent(
            [ExchangeRate].self,
            forKey: .exchangeRates
        ) ?? []
        budgets = try container.decodeIfPresent([LedgerBudget].self, forKey: .budgets) ?? []
        templates = try container.decodeIfPresent([LedgerTemplate].self, forKey: .templates) ?? []
        attachments = try container.decodeIfPresent([LedgerAttachment].self, forKey: .attachments) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accounts, forKey: .accounts)
        try container.encode(categories, forKey: .categories)
        try container.encode(transactions, forKey: .transactions)
        try container.encode(scheduledTransactions, forKey: .scheduledTransactions)
        try container.encode(exchangeRates, forKey: .exchangeRates)
        try container.encode(budgets, forKey: .budgets)
        try container.encode(templates, forKey: .templates)
        try container.encode(attachments, forKey: .attachments)
    }

    static var empty: FinanceData {
        FinanceData(accounts: [], categories: [], transactions: [], scheduledTransactions: [])
    }
}
