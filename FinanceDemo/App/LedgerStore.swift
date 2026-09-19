import Combine
import Foundation
import WidgetKit

@MainActor
final class LedgerStore: ObservableObject {
    @Published private(set) var data: FinanceData
    @Published private(set) var lastActionStatus: String?

    private let storage = FinanceStorage(context: "main-app")

    init() {
        data = storage.load()
    }

    var storageAvailable: Bool {
        storage.isPersistent && !storage.isCorrupted
    }

    var sharedStorageAvailable: Bool {
        storage.isAppGroupAvailable
    }

    var storageStatus: String {
        if storage.isCorrupted {
            return "Persistent database could not be decoded; restore or reset required"
        }
        if storage.isAppGroupAvailable {
            return "Persistent database is working"
        }
        if storage.isLocalFallback {
            return "Persistent local database is working; widget sharing is unavailable"
        }
        return "Persistent database unavailable"
    }

    var recentTransactions: [LedgerTransaction] {
        data.transactions.sorted { $0.date > $1.date }
    }

    var rootCategories: [LedgerCategory] {
        data.categories.filter { $0.parentID == nil && !$0.isArchived }
    }

    var activeAccounts: [Account] {
        data.accounts.filter { !$0.isArchived }
    }

    var activeCategories: [LedgerCategory] {
        data.categories.filter { !$0.isArchived }
    }

    var monthTransactionCount: Int {
        data.transactions.filter { transaction in
            transaction.date >= monthStart && transactionHasIncludedAccount(transaction)
        }.count
    }

    var topCategoryThisMonth: String? {
        var counts: [UUID: Int] = [:]
        for transaction in data.transactions where transaction.kind == .expense
            && transaction.date >= monthStart
            && transaction.outflows.contains(where: { includesInTotals(accountID: $0.accountID) }) {
            guard let categoryID = transaction.categoryID else { continue }
            counts[categoryID, default: 0] += 1
        }

        guard let categoryID = counts.max(by: { $0.value < $1.value })?.key else {
            return nil
        }
        return categoryPath(for: categoryID)
    }

    @discardableResult
    func addTransaction(_ transaction: LedgerTransaction) -> Bool {
        guard validate(transaction) else { return false }
        var updated = data
        updated.transactions.append(transaction)
        return persist(updated, successMessage: "Transaction saved")
    }

    @discardableResult
    func updateTransaction(_ transaction: LedgerTransaction) -> Bool {
        guard let index = data.transactions.firstIndex(where: { $0.id == transaction.id }) else {
            lastActionStatus = "Transaction not found"
            return false
        }

        guard validate(transaction, allowArchivedReferences: true) else { return false }

        var updated = data
        updated.transactions[index] = transaction
        return persist(updated, successMessage: "Transaction updated")
    }

    @discardableResult
    func deleteTransaction(id: UUID) -> Bool {
        var updated = data
        let originalCount = updated.transactions.count
        updated.transactions.removeAll { $0.id == id }
        guard updated.transactions.count != originalCount else {
            lastActionStatus = "Transaction not found"
            return false
        }
        return persist(updated, successMessage: "Transaction deleted")
    }

    @discardableResult
    func duplicateTransaction(id: UUID) -> Bool {
        guard let transaction = data.transactions.first(where: { $0.id == id }) else {
            lastActionStatus = "Transaction not found"
            return false
        }

        let duplicate = LedgerTransaction(
            note: transaction.note,
            kind: transaction.kind,
            categoryID: transaction.categoryID,
            amountDue: transaction.amountDue,
            outflows: transaction.outflows.map { MoneyMovement(accountID: $0.accountID, money: $0.money) },
            inflows: transaction.inflows.map { MoneyMovement(accountID: $0.accountID, money: $0.money) },
            exchangeRate: transaction.exchangeRate,
            changeAdjustment: transaction.changeAdjustment,
            attachmentIDs: transaction.attachmentIDs
        )
        guard validate(duplicate, allowArchivedReferences: true) else { return false }
        var updated = data
        updated.transactions.append(duplicate)
        return persist(updated, successMessage: "Transaction duplicated")
    }

    @discardableResult
    func addScheduledTransaction(_ scheduledTransaction: ScheduledTransaction) -> Bool {
        guard validate(scheduledTransaction.transactionTemplate) else { return false }
        var updated = data
        updated.scheduledTransactions.append(scheduledTransaction)

        guard persist(updated, successMessage: "Transaction scheduled") else { return false }
        if scheduledTransaction.isEnabled,
           scheduledTransaction.nextRunDate <= .now {
            processDueScheduledTransactions()
        }
        return true
    }

    @discardableResult
    func updateScheduledTransaction(_ scheduledTransaction: ScheduledTransaction) -> Bool {
        guard let index = data.scheduledTransactions.firstIndex(where: { $0.id == scheduledTransaction.id }) else {
            lastActionStatus = "Scheduled transaction not found"
            return false
        }
        guard validate(scheduledTransaction.transactionTemplate, allowArchivedReferences: true) else { return false }

        var updated = data
        updated.scheduledTransactions[index] = scheduledTransaction
        guard persist(updated, successMessage: "Scheduled transaction updated") else { return false }

        if scheduledTransaction.isEnabled,
           scheduledTransaction.nextRunDate <= .now {
            processDueScheduledTransactions()
        }
        return true
    }

    @discardableResult
    func setScheduledTransactionEnabled(id: UUID, isEnabled: Bool) -> Bool {
        guard let index = data.scheduledTransactions.firstIndex(where: { $0.id == id }) else {
            lastActionStatus = "Scheduled transaction not found"
            return false
        }

        var scheduledTransaction = data.scheduledTransactions[index]
        guard !(isEnabled && scheduledTransaction.frequency == .once && scheduledTransaction.lastRunDate != nil) else {
            lastActionStatus = "Completed one-time transactions cannot be re-enabled"
            return false
        }
        scheduledTransaction.isEnabled = isEnabled
        var updated = data
        updated.scheduledTransactions[index] = scheduledTransaction
        let persisted = persist(
            updated,
            successMessage: isEnabled ? "Scheduled transaction enabled" : "Scheduled transaction paused"
        )
        if persisted, isEnabled, scheduledTransaction.nextRunDate <= .now {
            processDueScheduledTransactions()
        }
        return persisted
    }

    @discardableResult
    func deleteScheduledTransaction(id: UUID) -> Bool {
        var updated = data
        let originalCount = updated.scheduledTransactions.count
        updated.scheduledTransactions.removeAll { $0.id == id }
        guard updated.scheduledTransactions.count != originalCount else {
            lastActionStatus = "Scheduled transaction not found"
            return false
        }
        return persist(updated, successMessage: "Scheduled transaction deleted")
    }

    @discardableResult
    func processDueScheduledTransactions(now: Date = .now) -> Int {
        var updated = data
        var materializedCount = 0
        var changed = false
        let calendar = Calendar.current

        for index in updated.scheduledTransactions.indices {
            var scheduledTransaction = updated.scheduledTransactions[index]
            guard scheduledTransaction.isEnabled else { continue }

            var dueDate = scheduledTransaction.nextRunDate
            while scheduledTransaction.isEnabled && dueDate <= now {
                updated.transactions.append(scheduledTransaction.materializedTransaction(on: dueDate))
                materializedCount += 1
                changed = true
                scheduledTransaction.lastRunDate = dueDate

                guard scheduledTransaction.frequency != .once else {
                    scheduledTransaction.isEnabled = false
                    break
                }

                guard let nextDate = scheduledTransaction.frequency.nextDate(
                    after: dueDate,
                    calendar: calendar,
                    monthlyDay: scheduledTransaction.recurrenceDay,
                    monthlyRule: scheduledTransaction.monthlyRule
                ),
                      nextDate > dueDate else {
                    scheduledTransaction.isEnabled = false
                    break
                }

                scheduledTransaction.nextRunDate = nextDate
                dueDate = nextDate
            }

            updated.scheduledTransactions[index] = scheduledTransaction
        }

        guard changed else { return 0 }
        guard persist(
            updated,
            successMessage: "Added \(materializedCount) scheduled transaction\(materializedCount == 1 ? "" : "s")"
        ) else { return 0 }
        return materializedCount
    }

    @discardableResult
    func addAccount(_ account: Account) -> Bool {
        guard !account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastActionStatus = "Enter an account name"
            return false
        }
        var updated = data
        updated.accounts.append(account)
        return persist(updated, successMessage: "Account added")
    }

    @discardableResult
    func updateAccount(_ account: Account) -> Bool {
        guard let index = data.accounts.firstIndex(where: { $0.id == account.id }) else {
            lastActionStatus = "Account not found"
            return false
        }
        guard !account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastActionStatus = "Enter an account name"
            return false
        }
        let original = data.accounts[index]
        let hasMovements = data.transactions.contains {
            ($0.outflows + $0.inflows).contains { $0.accountID == account.id }
        } || data.scheduledTransactions.contains {
            ($0.outflows + $0.inflows).contains { $0.accountID == account.id }
        }
        guard !hasMovements || original.currency == account.currency else {
            lastActionStatus = "An account with activity cannot change currency"
            return false
        }

        var updated = data
        updated.accounts[index] = account
        return persist(updated, successMessage: "Account updated")
    }

    @discardableResult
    func setAccountArchived(accountID: UUID, isArchived: Bool) -> Bool {
        guard let index = data.accounts.firstIndex(where: { $0.id == accountID }) else {
            lastActionStatus = "Account not found"
            return false
        }
        var updated = data
        updated.accounts[index].isArchived = isArchived
        return persist(
            updated,
            successMessage: isArchived ? "Account archived" : "Account restored"
        )
    }

    @discardableResult
    func setAccountIncludedInTotals(accountID: UUID, included: Bool) -> Bool {
        guard let accountIndex = data.accounts.firstIndex(where: { $0.id == accountID }) else {
            lastActionStatus = "Account not found"
            return false
        }

        var updated = data
        updated.accounts[accountIndex].includeInTotals = included
        return persist(
            updated,
            successMessage: included ? "Account included in totals" : "Account excluded from totals"
        )
    }

    @discardableResult
    func addCategory(_ category: LedgerCategory) -> Bool {
        guard !category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastActionStatus = "Enter a category name"
            return false
        }
        guard category.parentID == nil || data.categories.contains(where: { $0.id == category.parentID }) else {
            lastActionStatus = "Choose an existing parent category"
            return false
        }
        var updated = data
        updated.categories.append(category)
        return persist(updated, successMessage: "Category added")
    }

    @discardableResult
    func updateCategory(_ category: LedgerCategory) -> Bool {
        guard let index = data.categories.firstIndex(where: { $0.id == category.id }) else {
            lastActionStatus = "Category not found"
            return false
        }
        guard !category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastActionStatus = "Enter a category name"
            return false
        }
        guard category.parentID != category.id,
              category.parentID == nil || data.categories.contains(where: { $0.id == category.parentID }) else {
            lastActionStatus = "Choose a valid parent category"
            return false
        }
        guard !wouldCreateCategoryCycle(category) else {
            lastActionStatus = "A category cannot be its own ancestor"
            return false
        }

        var updated = data
        updated.categories[index] = category
        return persist(updated, successMessage: "Category updated")
    }

    @discardableResult
    func setCategoryArchived(categoryID: UUID, isArchived: Bool) -> Bool {
        guard let index = data.categories.firstIndex(where: { $0.id == categoryID }) else {
            lastActionStatus = "Category not found"
            return false
        }
        var updated = data
        updated.categories[index].isArchived = isArchived
        return persist(
            updated,
            successMessage: isArchived ? "Category archived" : "Category restored"
        )
    }

    @discardableResult
    func upsertBudget(_ budget: LedgerBudget) -> Bool {
        guard budget.monthlyLimit.minorUnits > 0,
              data.categories.contains(where: { $0.id == budget.categoryID }),
              budget.monthlyLimit.currency == budget.currency else {
            lastActionStatus = "Enter a valid budget"
            return false
        }

        var updated = data
        if let index = updated.budgets.firstIndex(where: { $0.id == budget.id }) {
            updated.budgets[index] = budget
        } else {
            updated.budgets.append(budget)
        }
        return persist(updated, successMessage: "Budget saved")
    }

    @discardableResult
    func deleteBudget(id: UUID) -> Bool {
        var updated = data
        let originalCount = updated.budgets.count
        updated.budgets.removeAll { $0.id == id }
        guard updated.budgets.count != originalCount else {
            lastActionStatus = "Budget not found"
            return false
        }
        return persist(updated, successMessage: "Budget deleted")
    }

    @discardableResult
    func addTemplate(_ template: LedgerTemplate) -> Bool {
        var updated = data
        updated.templates.append(template)
        return persist(updated, successMessage: "Template saved")
    }

    @discardableResult
    func deleteTemplate(id: UUID) -> Bool {
        var updated = data
        let originalCount = updated.templates.count
        updated.templates.removeAll { $0.id == id }
        guard updated.templates.count != originalCount else {
            lastActionStatus = "Template not found"
            return false
        }
        return persist(updated, successMessage: "Template deleted")
    }

    func budgetSpent(_ budget: LedgerBudget, in interval: DateInterval? = nil) -> Money {
        financeBudgetSpent(budget, in: data, interval: interval)
    }

    func budgetAllowance(_ budget: LedgerBudget, for interval: DateInterval? = nil) -> Money {
        financeBudgetAllowance(budget, in: data, interval: interval)
    }

    func exchangeRate(base: LedgerCurrency, quote: LedgerCurrency) -> ExchangeRate? {
        guard base != quote else { return nil }

        if let exact = data.exchangeRates.first(where: {
            $0.baseCurrency == base && $0.quoteCurrency == quote
        }) {
            return exact
        }

        guard let reverse = data.exchangeRates.first(where: {
            $0.baseCurrency == quote && $0.quoteCurrency == base
        }), reverse.quoteUnitsPerBaseUnit > 0 else {
            return nil
        }

        return ExchangeRate(
            baseCurrency: base,
            quoteCurrency: quote,
            quoteUnitsPerBaseUnit: Decimal(1) / reverse.quoteUnitsPerBaseUnit
        )
    }

    @discardableResult
    func upsertExchangeRate(_ exchangeRate: ExchangeRate) -> Bool {
        guard exchangeRate.baseCurrency != exchangeRate.quoteCurrency,
              exchangeRate.quoteUnitsPerBaseUnit > 0 else {
            lastActionStatus = "Enter a positive rate between two different currencies"
            return false
        }

        var updated = data
        updated.exchangeRates.removeAll {
            Set([
                $0.baseCurrency,
                $0.quoteCurrency
            ]) == Set([
                exchangeRate.baseCurrency,
                exchangeRate.quoteCurrency
            ])
        }
        updated.exchangeRates.append(exchangeRate)
        return persist(updated, successMessage: "Exchange rate saved")
    }

    @discardableResult
    func deleteExchangeRate(_ exchangeRate: ExchangeRate) -> Bool {
        var updated = data
        let originalCount = updated.exchangeRates.count
        updated.exchangeRates.removeAll { $0.id == exchangeRate.id }
        guard updated.exchangeRates.count != originalCount else {
            lastActionStatus = "Exchange rate not found"
            return false
        }
        return persist(updated, successMessage: "Exchange rate deleted")
    }

    @discardableResult
    func resetLedger() -> Bool {
        let saved = persist(.empty, successMessage: "Ledger reset", allowingCorruptedReplacement: true)
        if saved { storage.deleteAllAttachments() }
        return saved
    }

    @discardableResult
    func replaceData(_ imported: FinanceData, attachmentFiles: [UUID: Data] = [:]) -> Bool {
        let prepared = materializeAttachments(in: imported, files: attachmentFiles)
        guard validateImportedData(prepared) else { return false }
        let oldPaths = Set(data.attachments.map(\.relativePath))
        guard persist(prepared, successMessage: "Ledger restored", allowingCorruptedReplacement: true) else {
            return false
        }
        for path in oldPaths {
            storage.deleteAttachment(relativePath: path)
        }
        return true
    }

    @discardableResult
    func mergeData(_ imported: FinanceData, attachmentFiles: [UUID: Data] = [:]) -> Bool {
        let imported = materializeAttachments(in: imported, files: attachmentFiles)
        var updated = data
        let accountIDs = Set(updated.accounts.map(\.id))
        let categoryIDs = Set(updated.categories.map(\.id))
        let transactionIDs = Set(updated.transactions.map(\.id))
        let scheduledTransactionIDs = Set(updated.scheduledTransactions.map(\.id))
        let budgetIDs = Set(updated.budgets.map(\.id))
        let templateIDs = Set(updated.templates.map(\.id))
        let attachmentIDs = Set(updated.attachments.map(\.id))

        updated.accounts.append(contentsOf: imported.accounts.filter { !accountIDs.contains($0.id) })
        updated.categories.append(contentsOf: imported.categories.filter { !categoryIDs.contains($0.id) })
        updated.transactions.append(contentsOf: imported.transactions.filter { !transactionIDs.contains($0.id) })
        updated.scheduledTransactions.append(
            contentsOf: imported.scheduledTransactions.filter { !scheduledTransactionIDs.contains($0.id) }
        )
        updated.budgets.append(contentsOf: imported.budgets.filter { !budgetIDs.contains($0.id) })
        updated.templates.append(contentsOf: imported.templates.filter { !templateIDs.contains($0.id) })
        updated.attachments.append(contentsOf: imported.attachments.filter { !attachmentIDs.contains($0.id) })
        for rate in imported.exchangeRates {
            updated.exchangeRates.removeAll {
                Set([$0.baseCurrency, $0.quoteCurrency]) == Set([rate.baseCurrency, rate.quoteCurrency])
            }
            updated.exchangeRates.append(rate)
        }

        guard validateImportedData(updated) else { return false }
        return persist(updated, successMessage: "Import completed")
    }

    @discardableResult
    func addAttachment(
        data attachmentData: Data,
        fileName: String,
        contentType: String,
        receiptItems: [LedgerReceiptLineItem] = [],
        extractedTotal: Money? = nil
    ) -> LedgerAttachment? {
        do {
            let relativePath = try storage.storeAttachment(
                attachmentData,
                fileExtension: URL(fileURLWithPath: fileName).pathExtension
            )
            let attachment = LedgerAttachment(
                fileName: fileName,
                contentType: contentType,
                relativePath: relativePath,
                receiptItems: receiptItems,
                extractedTotal: extractedTotal
            )
            var updated = data
            updated.attachments.append(attachment)
            guard persist(updated, successMessage: "Attachment saved") else {
                storage.deleteAttachment(relativePath: relativePath)
                return nil
            }
            return attachment
        } catch {
            lastActionStatus = "Attachment could not be saved"
            return nil
        }
    }

    func attachmentData(for attachmentID: UUID) -> Data? {
        guard let attachment = data.attachments.first(where: { $0.id == attachmentID }) else {
            return nil
        }
        return storage.attachmentData(relativePath: attachment.relativePath)
    }

    func attachmentFiles() -> [UUID: Data] {
        data.attachments.reduce(into: [UUID: Data]()) { files, attachment in
            guard let data = attachmentData(for: attachment.id) else { return }
            files[attachment.id] = data
        }
    }

    @discardableResult
    func deleteAttachment(id: UUID) -> Bool {
        guard let attachment = data.attachments.first(where: { $0.id == id }) else {
            lastActionStatus = "Attachment not found"
            return false
        }
        var updated = data
        updated.attachments.removeAll { $0.id == id }
        updated.transactions = updated.transactions.map { transaction in
            var transaction = transaction
            transaction.attachmentIDs.removeAll { $0 == id }
            return transaction
        }
        guard persist(updated, successMessage: "Attachment deleted") else { return false }
        storage.deleteAttachment(relativePath: attachment.relativePath)
        return true
    }

    @discardableResult
    func replaceAttachment(
        id: UUID,
        data attachmentData: Data,
        fileName: String,
        contentType: String
    ) -> Bool {
        guard let index = data.attachments.firstIndex(where: { $0.id == id }) else {
            lastActionStatus = "Attachment not found"
            return false
        }

        do {
            let oldPath = data.attachments[index].relativePath
            let newPath = try storage.storeAttachment(
                attachmentData,
                fileExtension: URL(fileURLWithPath: fileName).pathExtension
            )
            var updated = data
            updated.attachments[index].fileName = fileName
            updated.attachments[index].contentType = contentType
            updated.attachments[index].relativePath = newPath
            guard persist(updated, successMessage: "Attachment replaced") else {
                storage.deleteAttachment(relativePath: newPath)
                return false
            }
            storage.deleteAttachment(relativePath: oldPath)
            return true
        } catch {
            lastActionStatus = "Attachment could not be replaced"
            return false
        }
    }

    private func materializeAttachments(in imported: FinanceData, files: [UUID: Data]) -> FinanceData {
        var prepared = imported
        for index in prepared.attachments.indices {
            let attachment = prepared.attachments[index]
            if let file = files[attachment.id],
               let relativePath = try? storage.storeAttachment(
                   file,
                   fileExtension: URL(fileURLWithPath: attachment.fileName).pathExtension
               ) {
                prepared.attachments[index].relativePath = relativePath
            } else {
                prepared.attachments[index].relativePath = "missing-\(attachment.id.uuidString)"
            }
        }
        return prepared
    }

    func reload() {
        data = storage.load()
    }

    func account(with id: UUID) -> Account? {
        data.accounts.first { $0.id == id }
    }

    func includesInTotals(accountID: UUID) -> Bool {
        account(with: accountID)?.includeInTotals ?? true
    }

    func transactionHasIncludedAccount(_ transaction: LedgerTransaction) -> Bool {
        (transaction.outflows + transaction.inflows).contains {
            includesInTotals(accountID: $0.accountID)
        }
    }

    func balance(for account: Account) -> Money {
        var balance = account.openingBalance.minorUnits

        for transaction in data.transactions {
            for movement in transaction.outflows where movement.accountID == account.id {
                guard movement.money.currency == account.currency else { continue }
                balance -= movement.money.minorUnits
            }
            for movement in transaction.inflows where movement.accountID == account.id {
                guard movement.money.currency == account.currency else { continue }
                balance += movement.money.minorUnits
            }
        }

        return Money(currency: account.currency, minorUnits: balance)
    }

    @discardableResult
    func updateAccountBalance(
        accountID: UUID,
        targetBalance: Money,
        recordAsTransaction: Bool,
        note: String
    ) -> Bool {
        guard let account = account(with: accountID),
              account.currency == targetBalance.currency else {
            lastActionStatus = "Balance update failed: currency mismatch."
            return false
        }

        let currentBalance = balance(for: account)
        let difference = targetBalance.minorUnits - currentBalance.minorUnits

        guard difference != 0 else {
            lastActionStatus = "Balance already matches"
            return true
        }

        var updated = data
        if recordAsTransaction {
            let adjustmentMoney = Money(
                currency: account.currency,
                minorUnits: Swift.abs(difference)
            )
            let adjustment = LedgerTransaction(
                date: .now,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Balance adjustment"
                    : note.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: difference > 0 ? .income : .expense,
                categoryID: nil,
                outflows: difference < 0
                    ? [MoneyMovement(accountID: account.id, money: adjustmentMoney)]
                    : [],
                inflows: difference > 0
                    ? [MoneyMovement(accountID: account.id, money: adjustmentMoney)]
                    : []
            )
            updated.transactions.append(adjustment)
        } else if let accountIndex = updated.accounts.firstIndex(where: { $0.id == accountID }) {
            updated.accounts[accountIndex].openingBalance = Money(
                currency: account.currency,
                minorUnits: account.openingBalance.minorUnits + difference
            )
        }

        return persist(
            updated,
            successMessage: recordAsTransaction
                ? "Balance adjustment saved as a transaction"
                : "Balance updated without a transaction"
        )
    }

    func availableBalance(for currency: LedgerCurrency) -> Money {
        let totalMinorUnits = data.accounts
            .filter { $0.currency == currency && $0.type != .loan && $0.includeInTotals }
            .reduce(Int64.zero) { $0 + balance(for: $1).minorUnits }
        return Money(currency: currency, minorUnits: totalMinorUnits)
    }

    func loanBalance(for currency: LedgerCurrency) -> Money {
        let totalMinorUnits = data.accounts
            .filter { $0.currency == currency && $0.type == .loan && $0.includeInTotals }
            .reduce(Int64.zero) { $0 + balance(for: $1).minorUnits }
        return Money(currency: currency, minorUnits: totalMinorUnits)
    }

    func assetBalance(for currency: LedgerCurrency) -> Money {
        availableBalance(for: currency)
    }

    func liabilityBalance(for currency: LedgerCurrency) -> Money {
        loanBalance(for: currency)
    }

    func netWorth(for currency: LedgerCurrency) -> Money {
        Money(
            currency: currency,
            minorUnits: assetBalance(for: currency).minorUnits - liabilityBalance(for: currency).minorUnits
        )
    }

    func monthlyExpenseTotals() -> [LedgerCurrency: Int64] {
        var totals: [LedgerCurrency: Int64] = [:]

        for transaction in data.transactions where transaction.kind == .expense && transaction.date >= monthStart {
            for currency in LedgerCurrency.allCases {
                totals[currency, default: 0] += financeNetExpenseAmount(
                    transaction,
                    currency: currency,
                    in: data
                )
            }
        }

        return totals
    }

    func categoryPath(for categoryID: UUID?) -> String {
        guard let categoryID else { return "Uncategorized" }

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

        return names.isEmpty ? "Uncategorized" : names.joined(separator: " / ")
    }

    private func validate(
        _ transaction: LedgerTransaction,
        allowArchivedReferences: Bool = false
    ) -> Bool {
        guard let error = FinanceTransactionValidator.validate(
            transaction,
            in: data,
            allowArchivedReferences: allowArchivedReferences
        ) else {
            return true
        }
        lastActionStatus = error.localizedDescription
        return false
    }

    private func wouldCreateCategoryCycle(_ category: LedgerCategory) -> Bool {
        var currentID = category.parentID
        var visited: Set<UUID> = [category.id]

        while let id = currentID {
            guard visited.insert(id).inserted else { return true }
            currentID = data.categories.first(where: { $0.id == id })?.parentID
        }
        return false
    }

    func transactionSummary(_ transaction: LedgerTransaction) -> String {
        let outflowText = transaction.outflows.map { $0.money.formatted }.joined(separator: " + ")
        let inflowText = transaction.inflows.map { $0.money.formatted }.joined(separator: " + ")

        if outflowText.isEmpty { return "+ \(inflowText)" }
        if inflowText.isEmpty { return "− \(outflowText)" }
        return "\(outflowText)  →  \(inflowText)"
    }

    private var monthStart: Date {
        Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .distantPast
    }

    @discardableResult
    private func persist(
        _ updated: FinanceData,
        successMessage: String,
        allowingCorruptedReplacement: Bool = false
    ) -> Bool {
        let persisted = storage.save(
            updated,
            allowingCorruptedReplacement: allowingCorruptedReplacement
        )
        guard persisted else {
            let reason = storage.isCorrupted
                ? "the persistent database could not be decoded; restore or reset it"
                : "the persistent database is unavailable"
            lastActionStatus = "\(successMessage) was not saved because \(reason)."
            return false
        }

        data = updated
        WidgetCenter.shared.reloadTimelines(ofKind: "BalanceWidget")
        FinanceDemoShortcuts.updateAppShortcutParameters()
        Task {
            await FinanceIntentIndexing.shared.refresh()
        }
        let schedules = updated.scheduledTransactions
        Task {
            await NotificationService.refreshScheduledTransactionNotifications(
                schedules: schedules
            )
        }
        lastActionStatus = successMessage
        return true
    }

    private func validateImportedData(_ imported: FinanceData) -> Bool {
        guard let error = FinanceDataValidator.validate(imported) else {
            return true
        }
        lastActionStatus = "Import rejected: \(error.localizedDescription)"
        return false
    }
}
