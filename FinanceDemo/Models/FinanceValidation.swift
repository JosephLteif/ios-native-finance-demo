import Foundation

enum FinanceTransactionValidationError: LocalizedError, Equatable {
    case noMovements
    case missingMovementAccount
    case archivedMovementAccount
    case movementCurrencyMismatch
    case nonPositiveMovement
    case missingCategory
    case archivedCategory
    case invalidAmountDue
    case invalidChange
    case missingAttachment
    case unbalancedTransfer
    case missingExchangeRate

    var errorDescription: String? {
        switch self {
        case .noMovements:
            return "Add at least one account movement."
        case .missingMovementAccount:
            return "Every movement must use an existing account."
        case .archivedMovementAccount:
            return "Choose an active account for this transaction."
        case .movementCurrencyMismatch:
            return "A movement amount must use its account's currency, or include a valid exchange rate."
        case .nonPositiveMovement:
            return "Movement amounts must be greater than zero."
        case .missingCategory:
            return "Choose an existing category or leave the expense uncategorized."
        case .archivedCategory:
            return "Choose an active category for this transaction."
        case .invalidAmountDue:
            return "The bill total must be greater than zero."
        case .invalidChange:
            return "Requested and actual change must use the same currency and cannot be negative."
        case .missingAttachment:
            return "Every transaction attachment must exist in the ledger."
        case .unbalancedTransfer:
            return "A same-currency transfer must send and receive the same amount."
        case .missingExchangeRate:
            return "Add an exchange rate for this cross-currency transaction."
        }
    }
}

enum FinanceTransactionValidator {
    static func validate(
        _ transaction: LedgerTransaction,
        in data: FinanceData,
        allowArchivedReferences: Bool = false
    ) -> FinanceTransactionValidationError? {
        let movements = transaction.outflows + transaction.inflows
        guard !movements.isEmpty else { return .noMovements }

        for movement in movements {
            guard let account = data.accounts.first(where: { $0.id == movement.accountID }) else {
                return .missingMovementAccount
            }
            if account.isArchived && !allowArchivedReferences {
                return .archivedMovementAccount
            }
            if movement.money.currency != account.currency,
               financeConvertedMinorUnits(
                   movement.money,
                   to: account.currency,
                   using: transaction.exchangeRate
               ) == nil {
                return .missingExchangeRate
            }
            guard movement.money.minorUnits > 0 else {
                return .nonPositiveMovement
            }
        }

        switch transaction.kind {
        case .expense:
            guard !transaction.outflows.isEmpty else { return .noMovements }
            if let categoryID = transaction.categoryID {
                guard let category = data.categories.first(where: { $0.id == categoryID }) else {
                    return .missingCategory
                }
                if category.isArchived && !allowArchivedReferences {
                    return .archivedCategory
                }
            }
        case .income:
            guard !transaction.inflows.isEmpty else { return .noMovements }
        case .transfer:
            guard !transaction.outflows.isEmpty, !transaction.inflows.isEmpty else {
                return .noMovements
            }
        }

        if let amountDue = transaction.amountDue, amountDue.minorUnits <= 0 {
            return .invalidAmountDue
        }

        if let change = transaction.changeAdjustment {
            guard change.requested.currency == change.actual.currency,
                  change.requested.minorUnits >= 0,
                  change.actual.minorUnits >= 0 else {
                return .invalidChange
            }
        }

        guard transaction.attachmentIDs.allSatisfy({ attachmentID in
            data.attachments.contains { $0.id == attachmentID }
        }) else {
            return .missingAttachment
        }

        let currencies = Set(movements.map { $0.money.currency })
        if transaction.kind == .transfer {
            if currencies.count == 1 {
                let outflowTotal = transaction.outflows.reduce(Int64.zero) { $0 + $1.money.minorUnits }
                let inflowTotal = transaction.inflows.reduce(Int64.zero) { $0 + $1.money.minorUnits }
                guard outflowTotal == inflowTotal else { return .unbalancedTransfer }
            } else if transaction.exchangeRate == nil {
                return .missingExchangeRate
            }
        }

        return nil
    }
}

enum FinanceDataValidationError: LocalizedError, Equatable {
    case duplicateIDs(String)
    case accountCurrencyMismatch(String)
    case categoryParentMissing(String)
    case categoryCycle(String)
    case invalidTransaction(index: Int, error: FinanceTransactionValidationError)
    case invalidScheduledTransaction(index: Int, error: FinanceTransactionValidationError)
    case invalidScheduleRule(index: Int)
    case invalidTemplate(index: Int, error: FinanceTransactionValidationError)
    case invalidBudget(index: Int)
    case invalidExchangeRate(index: Int)

    var errorDescription: String? {
        switch self {
        case .duplicateIDs(let collection):
            return "The backup contains duplicate IDs in \(collection)."
        case .accountCurrencyMismatch(let accountName):
            return "Account \"\(accountName)\" has an opening balance in the wrong currency."
        case .categoryParentMissing(let categoryName):
            return "Category \"\(categoryName)\" refers to a missing parent category."
        case .categoryCycle(let categoryName):
            return "Category \"\(categoryName)\" is part of a parent cycle."
        case .invalidTransaction(let index, let error):
            return "Transaction \(index + 1) is invalid: \(error.localizedDescription)"
        case .invalidScheduledTransaction(let index, let error):
            return "Scheduled transaction \(index + 1) is invalid: \(error.localizedDescription)"
        case .invalidScheduleRule(let index):
            return "Scheduled transaction \(index + 1) has an invalid monthly recurrence rule."
        case .invalidTemplate(let index, let error):
            return "Template \(index + 1) is invalid: \(error.localizedDescription)"
        case .invalidBudget(let index):
            return "Budget \(index + 1) has a missing category, invalid amount, or currency mismatch."
        case .invalidExchangeRate(let index):
            return "Exchange rate \(index + 1) is invalid."
        }
    }
}

enum FinanceDataValidator {
    static func validate(_ data: FinanceData, allowArchivedReferences: Bool = true) -> FinanceDataValidationError? {
        if hasDuplicateIDs(data.accounts.map(\.id)) {
            return .duplicateIDs("accounts")
        }
        if hasDuplicateIDs(data.categories.map(\.id)) {
            return .duplicateIDs("categories")
        }
        if hasDuplicateIDs(data.transactions.map(\.id)) {
            return .duplicateIDs("transactions")
        }
        if hasDuplicateIDs(data.scheduledTransactions.map(\.id)) {
            return .duplicateIDs("scheduled transactions")
        }
        if hasDuplicateIDs(data.budgets.map(\.id)) {
            return .duplicateIDs("budgets")
        }
        if hasDuplicateIDs(data.templates.map(\.id)) {
            return .duplicateIDs("templates")
        }
        if hasDuplicateIDs(data.attachments.map(\.id)) {
            return .duplicateIDs("attachments")
        }

        for account in data.accounts where account.openingBalance.currency != account.currency {
            return .accountCurrencyMismatch(account.name)
        }

        let categoriesByID = Dictionary(uniqueKeysWithValues: data.categories.map { ($0.id, $0) })
        for category in data.categories {
            if let parentID = category.parentID,
               categoriesByID[parentID] == nil {
                return .categoryParentMissing(category.name)
            }

            var visited: Set<UUID> = []
            var currentID: UUID? = category.id
            while let id = currentID {
                guard visited.insert(id).inserted else {
                    return .categoryCycle(category.name)
                }
                currentID = categoriesByID[id]?.parentID
            }
        }

        for (index, transaction) in data.transactions.enumerated() {
            if let error = FinanceTransactionValidator.validate(
                transaction,
                in: data,
                allowArchivedReferences: allowArchivedReferences
            ) {
                return .invalidTransaction(index: index, error: error)
            }
        }

        for (index, scheduledTransaction) in data.scheduledTransactions.enumerated() {
            if scheduledTransaction.recurrenceDay < 1 || scheduledTransaction.recurrenceDay > 31 {
                return .invalidScheduleRule(index: index)
            }
            if let error = FinanceTransactionValidator.validate(
                scheduledTransaction.transactionTemplate,
                in: data,
                allowArchivedReferences: allowArchivedReferences
            ) {
                return .invalidScheduledTransaction(index: index, error: error)
            }
        }

        for (index, template) in data.templates.enumerated() {
            if let error = FinanceTransactionValidator.validate(
                template.transactionTemplate,
                in: data,
                allowArchivedReferences: allowArchivedReferences
            ) {
                return .invalidTemplate(index: index, error: error)
            }
        }

        for (index, budget) in data.budgets.enumerated() {
            guard data.categories.contains(where: { $0.id == budget.categoryID }),
                  budget.monthlyLimit.currency == budget.currency,
                  budget.monthlyLimit.minorUnits > 0 else {
                return .invalidBudget(index: index)
            }
        }

        for (index, rate) in data.exchangeRates.enumerated() {
            guard rate.baseCurrency != rate.quoteCurrency,
                  rate.quoteUnitsPerBaseUnit > 0 else {
                return .invalidExchangeRate(index: index)
            }
        }

        return nil
    }

    private static func hasDuplicateIDs(_ ids: [UUID]) -> Bool {
        Set(ids).count != ids.count
    }
}
