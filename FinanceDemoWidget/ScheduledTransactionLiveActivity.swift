import ActivityKit
import SwiftUI
import WidgetKit

struct ScheduledTransactionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScheduledTransactionActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    context.state.totalItemsCount == 1
                        ? "Scheduled transaction"
                        : "Scheduled transactions",
                    systemImage: "calendar.badge.clock"
                )
                    .font(.headline)

                ForEach(context.state.items) { item in
                    HStack(alignment: .firstTextBaseline) {
                        Text(
                            item.dueDate,
                            format: .dateTime.month(.abbreviated).day().hour().minute()
                        )
                        .font(.subheadline.weight(.medium))

                        Spacer(minLength: 12)

                        countdown(to: item.dueDate)
                            .font(.title3.monospacedDigit().weight(.semibold))
                    }
                }

                if context.state.additionalItemsCount > 0 {
                    Text("And \(context.state.additionalItemsCount) more scheduled entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Due entries are added when you next open Pocket Ledger.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .padding(16)
            .activityBackgroundTint(Color(red: 0.08, green: 0.16, blue: 0.22))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.totalItemsCount) scheduled", systemImage: "calendar.badge.clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(to: context.state.items.first?.dueDate ?? context.attributes.primaryDueDate)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(context.state.items.prefix(2)) { item in
                            HStack {
                                Text(
                                    item.dueDate,
                                    format: .dateTime.month(.abbreviated).day().hour().minute()
                                )
                                Spacer()
                                countdown(to: item.dueDate)
                            }
                            .font(.caption.monospacedDigit())
                        }
                        if context.state.totalItemsCount > 2 {
                            Text("+\(context.state.totalItemsCount - 2) more")
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(.white)
                }
            } compactLeading: {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.teal)
            } compactTrailing: {
                countdown(to: context.state.items.first?.dueDate ?? context.attributes.primaryDueDate)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } minimal: {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.teal)
            }
            .keylineTint(.teal)
        }
    }

    @ViewBuilder
    private func countdown(to dueDate: Date) -> some View {
        if dueDate > .now {
            Text(timerInterval: Date.now...dueDate, countsDown: true)
        } else {
            Text("Due now")
        }
    }
}
