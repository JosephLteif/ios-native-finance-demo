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
            return "A movement amount must use its account's currency."
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
            return "Add an exchange rate for a cross-currency transfer."
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
            guard movement.money.currency == account.currency else {
                return .movementCurrencyMismatch
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
