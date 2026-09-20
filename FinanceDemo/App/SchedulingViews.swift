import SwiftUI

@MainActor
struct ScheduledTransactionsView: View {
    @ObservedObject var store: LedgerStore

    @State private var isPresentingEditor = false
    @State private var editingSchedule: ScheduledTransaction?
    @State private var scheduleToDelete: ScheduledTransaction?
    @State private var reminderStatus: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                screenHeader

                    Text("Due entries are added to Transactions when Pocket Ledger opens or returns to the foreground.")
                        .font(.footnote)
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                        .padding(.horizontal, 4)

                    if !schedules.isEmpty {
                        Button {
                            Task {
                                reminderStatus = await NotificationService
                                    .requestScheduledTransactionNotifications(
                                        schedules: schedules
                                    )
                            }
                        } label: {
                            Label("Enable due reminders", systemImage: "bell.badge")
                        }
                        .buttonStyle(.glass)
                        .tint(PocketLedgerTheme.accent)
                        .padding(.horizontal, 4)
                    }

                    if let reminderStatus {
                        Text(reminderStatus)
                            .font(.caption)
                            .foregroundStyle(PocketLedgerTheme.textTertiary)
                            .padding(.horizontal, 4)
                    }

                    if schedules.isEmpty {
                        emptyState
                    } else {
                        ForEach(schedules) { schedule in
                            scheduleCard(schedule)
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .pocketScreen()
        .navigationTitle("Scheduled")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingEditor, onDismiss: { editingSchedule = nil }) {
            TransactionEditor(
                store: store,
                initialTiming: .scheduled,
                scheduledTransaction: editingSchedule
            )
        }
        .confirmationDialog("Delete scheduled transaction?", isPresented: isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let scheduleToDelete {
                    _ = store.deleteScheduledTransaction(id: scheduleToDelete.id)
                }
                self.scheduleToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                scheduleToDelete = nil
            }
        } message: {
            Text(scheduleToDelete?.note ?? "")
        }
    }

    private var schedules: [ScheduledTransaction] {
        store.data.scheduledTransactions.sorted { lhs, rhs in
            if lhs.isEnabled != rhs.isEnabled {
                return lhs.isEnabled && !rhs.isEnabled
            }
            return lhs.nextRunDate < rhs.nextRunDate
        }
    }

    private var isShowingDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { scheduleToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    scheduleToDelete = nil
                }
            }
        )
    }

    private var screenHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scheduled")
                    .font(.largeTitle.weight(.semibold))
                Text("Plan bills, income, and recurring transfers")
                    .font(.subheadline)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
            }

            Spacer()

            Button(action: presentNewSchedule) {
                Image(systemName: "plus")
                    .font(.body.weight(.bold))
                    .foregroundStyle(PocketLedgerTheme.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .pocketGlassSurface(
                        cornerRadius: 22,
                        tint: PocketLedgerTheme.accent.opacity(0.18),
                        interactive: true
                    )
            }
            .accessibilityLabel("Add scheduled transaction")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(PocketLedgerTheme.textTertiary)
            Text("Nothing scheduled yet")
                .font(.headline)
            Text("Create a future or recurring transaction and it will be recorded automatically when the app is active.")
                .font(.subheadline)
                .foregroundStyle(PocketLedgerTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Create schedule", action: presentNewSchedule)
                .buttonStyle(.glassProminent)
                .tint(PocketLedgerTheme.accent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 20)
        .pocketGroupedSurface(cornerRadius: 20)
    }

    private func scheduleCard(_ schedule: ScheduledTransaction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(schedule.note.isEmpty ? schedule.kind.displayName : schedule.note)
                        .font(.headline)
                        .lineLimit(2)
                    Text(store.transactionSummary(schedule.transactionTemplate))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(PocketLedgerTheme.textPrimary)
                }

                Spacer(minLength: 8)

                Toggle(
                    "Enable \(schedule.note.isEmpty ? schedule.kind.displayName : schedule.note)",
                    isOn: enabledBinding(for: schedule)
                )
                .labelsHidden()
                .accessibilityValue(schedule.isEnabled ? "On" : "Off")
                .disabled(isCompletedOneTime(schedule))
            }

            HStack(spacing: 8) {
                Label(schedule.kind.displayName, systemImage: schedule.kind == .income ? "arrow.down.left" : "arrow.up.right")
                if schedule.kind == .expense {
                    Text("·")
                    Text(store.categoryPath(for: schedule.categoryID))
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(PocketLedgerTheme.textSecondary)

            Text(timingText(for: schedule))
                .font(.caption.weight(.semibold))
                .foregroundStyle(schedule.isEnabled ? PocketLedgerTheme.accent : PocketLedgerTheme.textTertiary)

            HStack {
                if schedule.isEnabled {
                    Menu {
                        Button("Record now", systemImage: "checkmark.circle") {
                            _ = store.recordScheduledTransactionNow(id: schedule.id)
                        }
                        Button("Skip next", systemImage: "forward.end") {
                            _ = store.skipNextScheduledTransaction(id: schedule.id)
                        }
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                    .buttonStyle(.glass)
                    .tint(PocketLedgerTheme.accent)
                }

                Button("Edit") {
                    editingSchedule = schedule
                    isPresentingEditor = true
                }
                .buttonStyle(.glass)
                .tint(PocketLedgerTheme.accent)

                Spacer()

                Button(role: .destructive) {
                    scheduleToDelete = schedule
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(16)
        .pocketGroupedSurface(cornerRadius: 20)
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(PocketLedgerTheme.divider, lineWidth: 1)
        }
    }

    private func timingText(for schedule: ScheduledTransaction) -> String {
        let date = schedule.nextRunDate.formatted(.dateTime.month(.abbreviated).day().year())
        if let skippedDate = schedule.lastSkippedDate,
           schedule.lastRunDate.map({ skippedDate > $0 }) ?? true {
            if schedule.frequency == .once {
                return "Skipped \(skippedDate.formatted(.dateTime.month(.abbreviated).day().year()))"
            }
            return "Skipped \(skippedDate.formatted(.dateTime.month(.abbreviated).day())) · Next \(date)"
        }
        if schedule.isEnabled {
            if schedule.frequency == .once {
                return "Runs on \(date)"
            }
            if schedule.frequency == .monthly,
               schedule.monthlyRule == .lastDayOfMonth {
                return "Next \(date) · Last day of each month"
            }
            return "Next \(date) · \(schedule.frequency.displayName)"
        }

        if isCompletedOneTime(schedule), let lastRunDate = schedule.lastRunDate {
            return "Completed \(lastRunDate.formatted(.dateTime.month(.abbreviated).day().year()))"
        }
        return "Paused · Next \(date)"
    }

    private func isCompletedOneTime(_ schedule: ScheduledTransaction) -> Bool {
        schedule.frequency == .once && schedule.lastRunDate != nil
    }

    private func enabledBinding(for schedule: ScheduledTransaction) -> Binding<Bool> {
        Binding(
            get: {
                store.data.scheduledTransactions.first { $0.id == schedule.id }?.isEnabled ?? false
            },
            set: { isEnabled in
                _ = store.setScheduledTransactionEnabled(id: schedule.id, isEnabled: isEnabled)
            }
        )
    }

    private func presentNewSchedule() {
        editingSchedule = nil
        isPresentingEditor = true
    }
}
