import SwiftUI
import WidgetKit

struct BalanceEntry: TimelineEntry, Sendable {
    let date: Date
    let snapshot: FinanceWidgetSnapshot
}

struct BalanceTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BalanceEntry {
        BalanceEntry(
            date: .now,
            snapshot: FinanceWidgetSnapshot(
                usdAvailable: Money(currency: .usd, minorUnits: 250_000),
                lbpAvailable: Money(currency: .lbp, minorUnits: 4_500_000),
                latestTransactionDescription: "Starter ledger",
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
                .foregroundStyle(.secondary)

            if entry.snapshot.appGroupAvailable {
                balanceRow(
                    currency: "USD",
                    amount: entry.snapshot.usdAvailable.formatted
                )
                balanceRow(
                    currency: "LBP",
                    amount: entry.snapshot.lbpAvailable.formatted
                )

                Text(entry.snapshot.latestTransactionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(family == .systemSmall ? 2 : 1)
            } else {
                Text("Shared storage unavailable")
                    .font(.headline)
                    .foregroundStyle(.orange)
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
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a five dollar USD expense")
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Shared App Group unavailable")
                }
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private func balanceRow(currency: String, amount: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(currency)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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
        .description("Shows available USD and LBP balances and the latest transaction.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BalanceWidgetBundle: WidgetBundle {
    var body: some Widget {
        BalanceWidget()
    }
}
