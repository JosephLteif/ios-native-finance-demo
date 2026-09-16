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

    init(
        id: UUID = UUID(),
        name: String,
        type: AccountType,
        currency: LedgerCurrency,
        openingBalance: Money,
        includeInTotals: Bool = true
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.currency = currency
        self.openingBalance = openingBalance
        self.includeInTotals = includeInTotals
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case currency
        case openingBalance
        case includeInTotals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(AccountType.self, forKey: .type)
        currency = try container.decode(LedgerCurrency.self, forKey: .currency)
        openingBalance = try container.decode(Money.self, forKey: .openingBalance)
        includeInTotals = try container.decodeIfPresent(Bool.self, forKey: .includeInTotals) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(currency, forKey: .currency)
        try container.encode(openingBalance, forKey: .openingBalance)
        try container.encode(includeInTotals, forKey: .includeInTotals)
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

    init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        systemImage: String = "tag"
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.systemImage = systemImage
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
        changeAdjustment: ChangeAdjustment? = nil
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

struct FinanceData: Codable, Equatable {
    var accounts: [Account]
    var categories: [LedgerCategory]
    var transactions: [LedgerTransaction]
    var scheduledTransactions: [ScheduledTransaction]
    var exchangeRates: [ExchangeRate]

    init(
        accounts: [Account],
        categories: [LedgerCategory],
        transactions: [LedgerTransaction],
        scheduledTransactions: [ScheduledTransaction] = [],
        exchangeRates: [ExchangeRate] = []
    ) {
        self.accounts = accounts
        self.categories = categories
        self.transactions = transactions
        self.scheduledTransactions = scheduledTransactions
        self.exchangeRates = exchangeRates
    }

    private enum CodingKeys: String, CodingKey {
        case accounts
        case categories
        case transactions
        case scheduledTransactions
        case exchangeRates
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
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accounts, forKey: .accounts)
        try container.encode(categories, forKey: .categories)
        try container.encode(transactions, forKey: .transactions)
        try container.encode(scheduledTransactions, forKey: .scheduledTransactions)
        try container.encode(exchangeRates, forKey: .exchangeRates)
    }

    static var empty: FinanceData {
        FinanceData(accounts: [], categories: [], transactions: [], scheduledTransactions: [])
    }
}
