import Foundation

#if os(iOS)
import WatchConnectivity
#endif

enum WatchSyncPublisher {
    static func makeSnapshot(from data: FinanceData, generatedAt: Date = .now) -> WatchLedgerSnapshot {
        func balance(for account: Account) -> Money {
            var minorUnits = account.openingBalance.minorUnits

            for transaction in data.transactions {
                for movement in transaction.outflows where movement.accountID == account.id {
                    guard let amount = financeConvertedMinorUnits(
                        movement.money,
                        to: account.currency,
                        using: transaction.exchangeRate
                    ) else { continue }
                    minorUnits -= amount
                }
                for movement in transaction.inflows where movement.accountID == account.id {
                    guard let amount = financeConvertedMinorUnits(
                        movement.money,
                        to: account.currency,
                        using: transaction.exchangeRate
                    ) else { continue }
                    minorUnits += amount
                }
            }

            return Money(currency: account.currency, minorUnits: minorUnits)
        }

        func categoryPath(for categoryID: UUID?) -> String? {
            guard let categoryID else { return nil }

            var names: [String] = []
            var currentID: UUID? = categoryID
            var visited: Set<UUID> = []

            while let id = currentID,
                  !visited.contains(id),
                  let category = data.categories.first(where: { $0.id == id }) {
                visited.insert(id)
                names.insert(category.name, at: 0)
                currentID = category.parentID
            }

            return names.isEmpty ? nil : names.joined(separator: " / ")
        }

        let accountsByID = Dictionary(uniqueKeysWithValues: data.accounts.map { ($0.id, $0) })
        let accountSummaries = data.accounts
            .filter { !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map {
                WatchAccountSummary(
                    id: $0.id,
                    name: $0.name,
                    currency: $0.currency,
                    balance: balance(for: $0),
                    canUseForExpense: !$0.isArchived && $0.type != .loan
                )
            }

        let categorySummaries = data.categories
            .filter { !$0.isArchived }
            .compactMap { category in
                categoryPath(for: category.id).map {
                    WatchCategorySummary(id: category.id, path: $0)
                }
            }
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }

        let transactionSummaries = data.transactions
            .sorted { $0.date > $1.date }
            .prefix(12)
            .compactMap { transaction -> WatchTransactionSummary? in
                guard let movement = (transaction.outflows + transaction.inflows).first,
                      let account = accountsByID[movement.accountID] else {
                    return nil
                }

                return WatchTransactionSummary(
                    id: transaction.id,
                    date: transaction.date,
                    note: transaction.note,
                    kind: transaction.kind.displayName,
                    amount: movement.money,
                    accountName: account.name,
                    categoryPath: categoryPath(for: transaction.categoryID)
                )
            }

        let balances = LedgerCurrency.allCases.map { currency in
            let totalMinorUnits = accountSummaries
                .filter { $0.currency == currency && $0.canUseForExpense }
                .reduce(Int64.zero) { $0 + $1.balance.minorUnits }
            return WatchBalanceSummary(
                currency: currency,
                balance: Money(currency: currency, minorUnits: totalMinorUnits)
            )
        }
        let attentionCount = data.transactions.filter {
            $0.kind == .expense && $0.categoryID == nil
        }.count
            + data.budgets.filter { budget in
                financeBudgetSpent(budget, in: data).minorUnits
                    > financeBudgetAllowance(budget, in: data).minorUnits
            }.count
        let upcomingScheduledCount = data.scheduledTransactions.filter {
            $0.isEnabled
                && $0.nextRunDate <= (Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now)
        }.count

        return WatchLedgerSnapshot(
            version: WatchLedgerSnapshot.currentVersion,
            generatedAt: generatedAt,
            balances: balances,
            accounts: accountSummaries,
            categories: categorySummaries,
            recentTransactions: Array(transactionSummaries),
            attentionCount: attentionCount,
            upcomingScheduledCount: upcomingScheduledCount
        )
    }

#if os(iOS)
    static func publish(data: FinanceData) {
        guard WCSession.isSupported() else { return }

        let snapshot = makeSnapshot(from: data)
        guard let context = WatchSyncCodec.dictionary(for: snapshot) else { return }

        DispatchQueue.main.async {
            let session = WCSession.default
            guard session.activationState == .activated,
                  session.isWatchAppInstalled else {
                return
            }

            try? session.updateApplicationContext(context)
            if session.isComplicationEnabled {
                session.transferCurrentComplicationUserInfo(context)
            }
        }
    }
#endif
}
