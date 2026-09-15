import AppIntents
import Foundation

struct FinanceAccountEntity: AppEntity, Hashable, Sendable {
    let id: UUID
    let name: String
    let currency: String
    let accountType: String

    init(account: Account) {
        id = account.id
        name = account.name
        currency = account.currency.rawValue
        accountType = account.type.displayName
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(currency) · \(accountType)"
        )
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = FinanceAccountQuery()
}

struct FinanceCategoryEntity: AppEntity, Hashable, Sendable {
    let id: UUID
    let name: String
    let path: String

    init(category: LedgerCategory, categories: [LedgerCategory]) {
        id = category.id
        name = category.name
        path = financeCategoryPath(for: category.id, in: categories)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(path)", subtitle: "Category")
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let defaultQuery = FinanceCategoryQuery()
}

struct FinanceAccountQuery: EntityStringQuery, Sendable {
    func entities(for identifiers: [FinanceAccountEntity.ID]) async throws -> [FinanceAccountEntity] {
        let accounts = FinanceStorage(context: "app-intent").load().accounts
        return identifiers.compactMap { identifier in
            accounts.first(where: { $0.id == identifier }).map(FinanceAccountEntity.init)
        }
    }

    func suggestedEntities() async throws -> [FinanceAccountEntity] {
        allEntities()
    }

    func entities(matching string: String) async throws -> [FinanceAccountEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return suggestedEntities()
        }

        return allEntities().filter { account in
            account.name.localizedCaseInsensitiveContains(query)
                || account.currency.localizedCaseInsensitiveContains(query)
                || account.accountType.localizedCaseInsensitiveContains(query)
        }
    }

    private func allEntities() -> [FinanceAccountEntity] {
        FinanceStorage(context: "app-intent")
            .load()
            .accounts
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(FinanceAccountEntity.init)
    }
}

struct FinanceCategoryQuery: EntityStringQuery, Sendable {
    func entities(for identifiers: [FinanceCategoryEntity.ID]) async throws -> [FinanceCategoryEntity] {
        let data = FinanceStorage(context: "app-intent").load()
        return identifiers.compactMap { identifier in
            data.categories.first(where: { $0.id == identifier }).map {
                FinanceCategoryEntity(category: $0, categories: data.categories)
            }
        }
    }

    func suggestedEntities() async throws -> [FinanceCategoryEntity] {
        allEntities()
    }

    func entities(matching string: String) async throws -> [FinanceCategoryEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return suggestedEntities()
        }

        return allEntities().filter { category in
            category.name.localizedCaseInsensitiveContains(query)
                || category.path.localizedCaseInsensitiveContains(query)
        }
    }

    private func allEntities() -> [FinanceCategoryEntity] {
        let data = FinanceStorage(context: "app-intent").load()
        return data.categories
            .map { FinanceCategoryEntity(category: $0, categories: data.categories) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

enum FinanceIntentTransactionKind: String, AppEnum, CaseIterable, Hashable, Sendable {
    case expense
    case income
    case transfer

    var ledgerKind: TransactionKind {
        switch self {
        case .expense:
            return .expense
        case .income:
            return .income
        case .transfer:
            return .transfer
        }
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Transaction type"
    static let caseDisplayRepresentations: [FinanceIntentTransactionKind: DisplayRepresentation] = [
        .expense: DisplayRepresentation(title: "Expense"),
        .income: DisplayRepresentation(title: "Income"),
        .transfer: DisplayRepresentation(title: "Transfer")
    ]
}

enum FinanceIntentCurrency: String, AppEnum, CaseIterable, Hashable, Sendable {
    case usd = "USD"
    case lbp = "LBP"

    var ledgerCurrency: LedgerCurrency {
        switch self {
        case .usd:
            return .usd
        case .lbp:
            return .lbp
        }
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Currency"
    static let caseDisplayRepresentations: [FinanceIntentCurrency: DisplayRepresentation] = [
        .usd: DisplayRepresentation(title: "USD", subtitle: "US Dollar"),
        .lbp: DisplayRepresentation(title: "LBP", subtitle: "Lebanese Pound")
    ]
}

func financeCategoryPath(for categoryID: UUID, in categories: [LedgerCategory]) -> String {
    var names: [String] = []
    var currentID: UUID? = categoryID
    var visited: Set<UUID> = []

    while let id = currentID,
          !visited.contains(id),
          let category = categories.first(where: { $0.id == id }) {
        visited.insert(id)
        names.insert(category.name, at: 0)
        currentID = category.parentID
    }

    return names.isEmpty ? "Uncategorized" : names.joined(separator: " / ")
}
