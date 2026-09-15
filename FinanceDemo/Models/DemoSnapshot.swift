import Foundation

struct DemoSnapshot: Equatable, Sendable {
    let balanceCents: Int
    let lastTransactionDescription: String
    let lastUpdated: Date
    let lastWidgetRefresh: Date?
    let appGroupAvailable: Bool
    let appStorageAvailable: Bool

    var balanceText: String {
        let absoluteCents = abs(balanceCents)
        let wholeDollars = absoluteCents / 100
        let cents = absoluteCents % 100
        let sign = balanceCents < 0 ? "-" : ""
        let digits = String(wholeDollars)
        var grouped = ""

        for (index, character) in digits.enumerated() {
            if index > 0 && (digits.count - index).isMultiple(of: 3) {
                grouped.append(",")
            }
            grouped.append(character)
        }

        guard cents > 0 else {
            return "\(sign)$\(grouped)"
        }

        return "\(sign)$\(grouped)\(String(format: ".%02d", cents))"
    }

    var appGroupStatusText: String {
        appGroupAvailable ? "WORKING" : "UNAVAILABLE"
    }
}
