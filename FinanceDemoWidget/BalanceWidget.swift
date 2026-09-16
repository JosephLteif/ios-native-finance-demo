import SwiftUI
import WidgetKit

private enum PocketWidgetTheme {
    static let background = Color(red: 0.04, green: 0.08, blue: 0.13)
    static let accent = Color(red: 0.20, green: 0.78, blue: 0.70)
    static let income = Color(red: 0.37, green: 0.66, blue: 1.00)
    static let warning = Color(red: 0.96, green: 0.70, blue: 0.32)
}

struct BalanceEntry: TimelineEntry, Sendable {
    let date: Date
    let snapshot: FinanceWidgetSnapshot
}

struct BalanceTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BalanceEntry {
        BalanceEntry(
            date: .now,
            snapshot: FinanceWidgetSnapshot(
                usdAvailable: Money(currency: .usd, minorUnits: 0),
                lbpAvailable: Money(currency: .lbp, minorUnits: 0),
                eurAvailable: Money(currency: .eur, minorUnits: 0),
                latestTransactionDescription: "No transactions yet",
                lastUpdated: .now,
                appGroupAvailable: true
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
        completion(
            BalanceEntry(
                date: .now,
                snapshot: FinanceStorage(context: "widget").widgetSnapshot()
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
        let entry = BalanceEntry(
            date: .now,
            snapshot: FinanceStorage(context: "widget").widgetSnapshot()
        )
        let refreshDate = Date(timeIntervalSinceNow: 15 * 60)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct BalanceWidgetEntryView: View {
    let entry: BalanceEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Pocket Ledger")
                .font(.caption)
                .foregroundStyle(PocketWidgetTheme.accent)

            if entry.snapshot.appGroupAvailable {
                balanceRow(
                    currency: "USD",
                    amount: entry.snapshot.usdAvailable.formatted
                )
                balanceRow(
                    currency: "LBP",
                    amount: entry.snapshot.lbpAvailable.formatted
                )
                balanceRow(
                    currency: "EUR",
                    amount: entry.snapshot.eurAvailable.formatted
                )

                Text(entry.snapshot.latestTransactionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(family == .systemSmall ? 2 : 1)
            } else {
                Text("Shared storage unavailable")
                    .font(.headline)
                    .foregroundStyle(PocketWidgetTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Sign both targets with the Pocket Ledger App Group to share balances.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                if entry.snapshot.appGroupAvailable {
                    Text(entry.snapshot.lastUpdated, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("App Group required")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if entry.snapshot.appGroupAvailable {
                    Button(intent: AddDemoExpenseIntent()) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(PocketWidgetTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a five dollar USD expense")
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(PocketWidgetTheme.warning)
                        .accessibilityLabel("Shared App Group unavailable")
                }
            }
        }
        .containerBackground(PocketWidgetTheme.background, for: .widget)
    }

    private func balanceRow(currency: String, amount: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(currency)
                .font(.caption.weight(.semibold))
            .foregroundStyle(currency == "USD" ? PocketWidgetTheme.income : Color.white.opacity(0.62))
            Spacer(minLength: 6)
            Text(amount)
                .font(.system(
                    size: family == .systemSmall ? 17 : 21,
                    weight: .bold,
                    design: .rounded
                ))
                .minimumScaleFactor(0.55)
                .lineLimit(1)
        }
    }
}

struct BalanceWidget: Widget {
    static let kind = "BalanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: BalanceTimelineProvider()) { entry in
            BalanceWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Pocket Ledger Balances")
        .description("Shows available USD, LBP, and EUR balances and the latest transaction.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BalanceWidgetBundle: WidgetBundle {
    var body: some Widget {
        BalanceWidget()
        AddExpenseControl()
    }
}
