import SwiftUI
import WidgetKit

struct BalanceEntry: TimelineEntry {
    let date: Date
    let snapshot: DemoSnapshot
}

struct BalanceTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BalanceEntry {
        BalanceEntry(
            date: .now,
            snapshot: DemoSnapshot(
                balanceCents: 100_000,
                lastTransactionDescription: "Starting balance",
                lastUpdated: .now,
                lastWidgetRefresh: nil,
                appGroupAvailable: true
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
        completion(BalanceEntry(date: .now, snapshot: DemoSharedStorage(context: "widget").snapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
        let entry = BalanceEntry(date: .now, snapshot: DemoSharedStorage(context: "widget").snapshot())
        let refreshDate = Date(timeIntervalSinceNow: 15 * 60)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct BalanceWidgetEntryView: View {
    let entry: BalanceEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Finance Demo")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(entry.snapshot.balanceText)
                .font(.system(size: family == .systemSmall ? 30 : 38, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.65)
                .lineLimit(1)

            Text(entry.snapshot.lastTransactionDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(family == .systemSmall ? 2 : 1)

            Spacer(minLength: 0)

            HStack {
                Text(entry.snapshot.lastUpdated, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if entry.snapshot.appGroupAvailable {
                    Button(intent: AddDemoExpenseIntent()) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a five dollar expense")
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Shared App Group unavailable")
                }
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

struct BalanceWidget: Widget {
    static let kind = "BalanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: BalanceTimelineProvider()) { entry in
            BalanceWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Demo Balance")
        .description("Shows the shared demo balance and last transaction.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BalanceWidgetBundle: WidgetBundle {
    var body: some Widget {
        BalanceWidget()
    }
}

