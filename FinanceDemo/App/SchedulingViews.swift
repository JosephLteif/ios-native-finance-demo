import SwiftUI

@MainActor
struct ScheduledTransactionsView: View {
    @ObservedObject var store: LedgerStore

    @State private var isPresentingEditor = false
    @State private var editingSchedule: ScheduledTransaction?
    @State private var scheduleToDelete: ScheduledTransaction?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    screenHeader

                    Text("Due entries are added to Transactions when Pocket Ledger opens or returns to the foreground.")
                        .font(.footnote)
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                        .padding(.horizontal, 4)

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
            .toolbar(.hidden, for: .navigationBar)
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
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Text("Plan bills, income, and recurring transfers")
                    .font(.subheadline)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
            }

            Spacer()

            Button(action: presentNewSchedule) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(PocketLedgerTheme.background)
                    .frame(width: 42, height: 42)
                    .background(PocketLedgerTheme.accent, in: Circle())
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
                .buttonStyle(.borderedProminent)
                .tint(PocketLedgerTheme.accent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 20)
        .background(PocketLedgerTheme.surface, in: RoundedRectangle(cornerRadius: 20))
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

                Toggle("", isOn: enabledBinding(for: schedule))
                .labelsHidden()
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
                Button("Edit") {
                    editingSchedule = schedule
                    isPresentingEditor = true
                }
                .buttonStyle(.bordered)
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
        .background(PocketLedgerTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(PocketLedgerTheme.divider, lineWidth: 1)
        }
    }

    private func timingText(for schedule: ScheduledTransaction) -> String {
        let date = schedule.nextRunDate.formatted(.dateTime.month(.abbreviated).day().year())
        if schedule.isEnabled {
            return schedule.frequency == .once
                ? "Runs on \(date)"
                : "Next \(date) · \(schedule.frequency.displayName)"
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
