import Foundation

enum LedgerCurrency: String, Codable, CaseIterable, Identifiable, Hashable {
    case usd = "USD"
    case lbp = "LBP"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usd:
            return "US Dollar"
        case .lbp:
            return "Lebanese Pound"
        }
    }

    var fractionDigits: Int {
        switch self {
        case .usd:
            return 2
        case .lbp:
            return 0
        }
    }

    var minorUnitScale: Int64 {
        switch self {
        case .usd:
            return 100
        case .lbp:
            return 1
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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cash:
            return "Cash"
        case .bankAccount:
            return "Bank account"
        case .loan:
            return "Loan"
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
        }
    }
}

struct Account: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var type: AccountType
    var currency: LedgerCurrency
    var openingBalance: Money

    init(
        id: UUID = UUID(),
        name: String,
        type: AccountType,
        currency: LedgerCurrency,
        openingBalance: Money
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.currency = currency
        self.openingBalance = openingBalance
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

struct ExchangeRate: Codable, Equatable {
    var baseCurrency: LedgerCurrency
    var quoteCurrency: LedgerCurrency
    var quoteUnitsPerBaseUnit: Decimal

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

struct FinanceWidgetSnapshot: Equatable, Sendable {
    let usdAvailable: Money
    let lbpAvailable: Money
    let latestTransactionDescription: String
    let lastUpdated: Date
    let appGroupAvailable: Bool

    var balanceSummary: String {
        "\(usdAvailable.formatted) · \(lbpAvailable.formatted)"
    }
}

struct FinanceData: Codable, Equatable {
    var accounts: [Account]
    var categories: [LedgerCategory]
    var transactions: [LedgerTransaction]

    static var starter: FinanceData {
        let food = LedgerCategory(name: "Food", systemImage: "fork.knife")
        let housing = LedgerCategory(name: "Housing", systemImage: "house")
        let transport = LedgerCategory(name: "Transport", systemImage: "car")
        let shopping = LedgerCategory(name: "Shopping", systemImage: "bag")
        let health = LedgerCategory(name: "Health", systemImage: "cross.case")

        return FinanceData(
            accounts: [
                Account(
                    name: "Cash — USD",
                    type: .cash,
                    currency: .usd,
                    openingBalance: Money(currency: .usd, minorUnits: 50_000)
                ),
                Account(
                    name: "Cash — LBP",
                    type: .cash,
                    currency: .lbp,
                    openingBalance: Money(currency: .lbp, minorUnits: 1_500_000)
                ),
                Account(
                    name: "Bank — USD",
                    type: .bankAccount,
                    currency: .usd,
                    openingBalance: Money(currency: .usd, minorUnits: 200_000)
                ),
                Account(
                    name: "Bank — LBP",
                    type: .bankAccount,
                    currency: .lbp,
                    openingBalance: Money(currency: .lbp, minorUnits: 3_000_000)
                ),
                Account(
                    name: "Family loan",
                    type: .loan,
                    currency: .usd,
                    openingBalance: Money(currency: .usd, minorUnits: 0)
                )
            ],
            categories: [
                food,
                LedgerCategory(name: "Groceries", parentID: food.id, systemImage: "cart"),
                LedgerCategory(name: "Restaurants", parentID: food.id, systemImage: "fork.knife.circle"),
                housing,
                LedgerCategory(name: "Rent", parentID: housing.id, systemImage: "house.fill"),
                LedgerCategory(name: "Utilities", parentID: housing.id, systemImage: "bolt"),
                transport,
                LedgerCategory(name: "Fuel", parentID: transport.id, systemImage: "fuelpump"),
                LedgerCategory(name: "Taxi", parentID: transport.id, systemImage: "car.fill"),
                shopping,
                LedgerCategory(name: "Clothing", parentID: shopping.id, systemImage: "tshirt"),
                health,
                LedgerCategory(name: "Pharmacy", parentID: health.id, systemImage: "pills")
            ],
            transactions: []
        )
    }
}
