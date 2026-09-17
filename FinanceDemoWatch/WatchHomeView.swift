import SwiftUI

struct WatchHomeView: View {
    @ObservedObject var store: WatchLedgerStore
    @State private var isShowingExpense = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(store.status.title, systemImage: store.status.systemImage)
                        .foregroundStyle(store.status == .error ? Color.orange : Color.secondary)

                    if let lastSyncedAt = store.lastSyncedAt {
                        Text("Updated \(lastSyncedAt, style: .relative)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage = store.errorMessage {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button {
                        isShowingExpense = true
                    } label: {
                        Label("Add expense", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.snapshot?.accounts.contains(where: \.canUseForExpense) != true)

                    if !store.pendingExpenses.isEmpty {
                        Text("\(store.pendingExpenses.count) expense queued")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let snapshot = store.snapshot {
                    Section("Balances") {
                        ForEach(snapshot.balances) { balance in
                            HStack {
                                Text(balance.currency.rawValue)
                                Spacer()
                                Text(balance.balance.formatted)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                    .privacySensitive()
                            }
                        }
                    }

                    Section("Recent") {
                        if snapshot.recentTransactions.isEmpty {
                            Text("No transactions yet")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(snapshot.recentTransactions) { transaction in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(transaction.note)
                                            .lineLimit(1)
                                            .privacySensitive()
                                        Spacer()
                                        Text(transaction.amount.formatted)
                                            .fontWeight(.semibold)
                                            .monospacedDigit()
                                            .privacySensitive()
                                    }
                                    Text(transaction.categoryPath ?? transaction.kind)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        Text("Open Pocket Ledger on your iPhone to sync your ledger.")
                            .foregroundStyle(.secondary)
                    }
                }

            }
            .navigationTitle("Pocket Ledger")
        }
        .sheet(isPresented: $isShowingExpense) {
            NavigationStack {
                WatchExpenseView(store: store)
            }
        }
    }
}
