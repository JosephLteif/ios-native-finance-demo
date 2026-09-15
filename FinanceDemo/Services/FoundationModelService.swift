import Foundation
import FoundationModels

enum FoundationModelService {
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

    static func generateBudgetSummary() async -> String {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            return "Generation skipped: \(availabilityDescription())."
        }

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(
                to: "Give me a one sentence summary of this budget: income $1,000, expenses $250, savings $750."
            )
            let summary = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.isEmpty ? "The model returned an empty response." : summary
        } catch {
            return "Generation failed: \(error.localizedDescription)"
        }
    }
}

