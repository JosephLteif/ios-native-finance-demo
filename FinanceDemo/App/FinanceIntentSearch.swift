import AppIntents
import Combine
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

@MainActor
final class FinanceIntentSearchRouter: ObservableObject {
    static let shared = FinanceIntentSearchRouter()

    struct SearchRequest: Equatable {
        let id: UUID
        let query: String
    }

    @Published private(set) var pendingSearch: SearchRequest?

    func showSearch(for query: String) {
        pendingSearch = SearchRequest(id: UUID(), query: query)
    }

    func consumePendingSearch() -> SearchRequest? {
        defer { pendingSearch = nil }
        return pendingSearch
    }
}

struct FinanceTransactionIntentValueQuery: IntentValueQuery {
    func values(for input: StringSearchCriteria) async throws -> [FinanceTransactionEntity] {
        let query = input.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        let storage = FinanceStorage(context: "app-intent")
        guard storage.isPersistent else { return [] }

        let data = storage.load()
        guard !storage.isCorrupted else { return [] }

        return Array(
            data.transactions
                .sorted { $0.date > $1.date }
                .map { FinanceTransactionEntity(transaction: $0, data: data) }
                .filter { $0.matchesSearch(query) }
                .prefix(25)
        )
    }
}

struct FinanceAccountIntentValueQuery: IntentValueQuery {
    func values(for input: StringSearchCriteria) async throws -> [FinanceAccountEntity] {
        let query = input.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        let storage = FinanceStorage(context: "app-intent")
        guard storage.isPersistent else { return [] }

        let data = storage.load()
        guard !storage.isCorrupted else { return [] }

        let matches = data.accounts
            .filter { !$0.isArchived }
            .map { account in
                FinanceAccountEntity(
                    account: account,
                    balance: financeAccountBalance(for: account, in: data)
                )
            }
            .filter { account in
                [account.name, account.currency, account.accountType, account.balance]
                    .contains { $0.localizedCaseInsensitiveContains(query) }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return Array(matches.prefix(10))
    }
}

@available(iOS 27.0, *)
@AppIntent(schema: .system.searchInApp)
struct SearchPocketLedgerIntent: ShowInAppSearchResultsIntent {
    static let title: LocalizedStringResource = "Search Pocket Ledger"
    static let description = IntentDescription("Search saved accounts, categories, and transactions in Pocket Ledger.")
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            FinanceIntentSearchRouter.shared.showSearch(for: criteria.term)
        }
        return .result()
    }
}

extension FinanceTransactionEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { entity in
            let details = [
                "Transaction: \(entity.note.isEmpty ? entity.kind : entity.note)",
                "Type: \(entity.kind)",
                "Date: \(entity.date.formatted(date: .abbreviated, time: .shortened))",
                "Amount: \(entity.amount)",
                "Category: \(entity.category)",
                "Accounts: \(entity.accountNames)"
            ]
            return Data(details.joined(separator: "\n").utf8)
        }
    }
}

extension FinanceAccountEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { entity in
            Data(
                "Account: \(entity.name)\nType: \(entity.accountType)\nBalance: \(entity.balance)"
                    .utf8
            )
        }
    }
}
