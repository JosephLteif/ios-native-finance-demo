import Foundation
import FoundationModels

enum FoundationModelService {
    struct ReceiptItem: Sendable {
        let name: String
        let quantity: Int
        let unitPriceText: String?
        let lineTotalText: String?
    }

    struct ReceiptAnalysis: Sendable {
        enum Status: Sendable {
            case applied
            case unavailable(String)
            case failed(String)
        }

        let items: [ReceiptItem]
        let status: Status
    }

    @Generable
    struct ReceiptExtraction {
        @Guide(description: "Every priced purchased product or service, excluding all receipt metadata and summary rows.")
        let items: [ReceiptItemPayload]
    }

    @Generable
    struct ReceiptItemPayload {
        @Guide(description: "The cleaned product or service name, not an address, phone number, date, ID, subtotal, tax, or total.")
        let name: String
        @Guide(description: "A positive whole-number quantity; use 1 when the receipt does not show a quantity.")
        let quantity: Int
        @Guide(description: "The visible unit price as plain numeric text, or an empty string when it is not visible.")
        let unitPrice: String
        @Guide(description: "The visible line total as plain numeric text, or an empty string when it is not visible.")
        let lineTotal: String
    }

    static func availabilityDescription() -> String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Available"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence disabled"
        case .unavailable(.deviceNotEligible):
            return "Device not eligible"
        case .unavailable(.modelNotReady):
            return "Model not ready"
        case .unavailable(let other):
            return "Unavailable (other: \(other))"
        }
    }

    static func generateBudgetSummary(for snapshot: FinanceWidgetSnapshot) async -> String {
        await generateBudgetSummary(
            balance: snapshot.balanceSummary,
            latestTransaction: snapshot.latestTransactionDescription
        )
    }

    static func analyzeReceipt(text: String) async -> ReceiptAnalysis {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return ReceiptAnalysis(
                items: [],
                status: .failed("Apple Intelligence did not receive enough receipt text, so Vision OCR was used instead.")
            )
        }

        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            return ReceiptAnalysis(
                items: [],
                status: .unavailable(receiptAvailabilityMessage(for: model.availability))
            )
        }

        do {
            let session = LanguageModelSession()
            let prompt = """
            Extract only purchased line items from this shopping receipt OCR.

            Return only the requested structured receipt items, with no explanation.
            The result must contain an items array with name, quantity, unitPrice, and lineTotal fields.

            Rules:
            - Include every product or service that was purchased and has a visible price.
            - Exclude store names, addresses, street numbers, phone numbers, dates, times, invoice or receipt numbers, tax IDs, card or payment details, loyalty numbers, cashier or terminal details, subtotal, tax, discount, change, payment, and grand total lines.
            - Use quantity 1 when no quantity is visible. Use the exact numeric values from the OCR; do not invent missing prices.
            - Include unitPrice when visible and lineTotal when visible. If only one price is visible, put it in lineTotal.
            - Clean obvious OCR noise from item names, but do not create an item that is not supported by the OCR.
            - If there are no priced purchased items, return {"items":[]}.

            Receipt OCR:
            \(trimmedText.prefix(9000))
            """
            let response = try await session.respond(
                to: prompt,
                generating: ReceiptExtraction.self
            )
            let items = response.content.items.compactMap(validReceiptItem)
            guard !items.isEmpty else {
                return ReceiptAnalysis(
                    items: [],
                    status: .failed("Apple Intelligence found no usable priced items, so Vision OCR was used instead.")
                )
            }
            return ReceiptAnalysis(items: items, status: .applied)
        } catch {
            return ReceiptAnalysis(
                items: [],
                status: .failed("Apple Intelligence could not finish this scan, so Vision OCR was used instead.")
            )
        }
    }

    private static func generateBudgetSummary(
        balance: String,
        latestTransaction: String
    ) async -> String {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            return "Generation skipped: \(availabilityDescription())."
        }

        do {
            let session = LanguageModelSession()
            let prompt = """
            Give me one concise sentence about this current Pocket Ledger snapshot. Use only the supplied data and do not invent totals.
            Current balances: \(balance)
            Last transaction: \(latestTransaction)
            """
            let response = try await session.respond(
                to: prompt
            )
            let summary = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.isEmpty ? "The model returned an empty response." : summary
        } catch {
            return "Generation failed: \(error.localizedDescription)"
        }
    }

    private static func receiptAvailabilityMessage(
        for availability: SystemLanguageModel.Availability
    ) -> String {
        switch availability {
        case .available:
            return "Apple Intelligence is available."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is turned off, so Vision OCR was used instead. Review the items before saving."
        case .unavailable(.deviceNotEligible):
            return "This device cannot use Apple Intelligence, so Vision OCR was used instead. Review the items before saving."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still preparing on this device, so Vision OCR was used instead. Try again later for cleanup."
        case .unavailable:
            return "Apple Intelligence is unavailable right now, so Vision OCR was used instead. Review the items before saving."
        }
    }

    private static func validReceiptItem(_ payload: ReceiptItemPayload) -> ReceiptItem? {
        let name = payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 2,
              name.count <= 120,
              name.rangeOfCharacter(from: .letters) != nil,
              (1...99).contains(payload.quantity),
              !isMetadataName(name) else {
            return nil
        }

        let unitPriceText = normalizedAmountText(payload.unitPrice)
        let lineTotalText = normalizedAmountText(payload.lineTotal)
        guard unitPriceText != nil || lineTotalText != nil else { return nil }

        return ReceiptItem(
            name: name,
            quantity: payload.quantity,
            unitPriceText: unitPriceText,
            lineTotalText: lineTotalText
        )
    }

    private static func normalizedAmountText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.rangeOfCharacter(from: .decimalDigits) != nil else {
            return nil
        }
        return normalized
    }

    private static func isMetadataName(_ name: String) -> Bool {
        let lowercasedName = name.lowercased()
        let ignoredPhrases = [
            "subtotal", "total", "tax", "vat", "discount", "change", "cash",
            "credit", "debit", "invoice", "receipt", "phone", "tel", "date",
            "time", "address", "street", "road", "avenue", "boulevard",
            "terminal", "cashier", "transaction", "reference", "order"
        ]
        return ignoredPhrases.contains(where: lowercasedName.contains)
    }
}
