import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var store = DemoStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    balanceCard
                    actionGrid
                    diagnosticsCard
                    intelligenceCard
                    notificationCard
                }
                .padding()
            }
            .navigationTitle("Finance Demo")
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Finance Native Demo")
                .font(.title2.weight(.semibold))
            Text(store.snapshot.balanceText)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .accessibilityIdentifier("demo-balance")
            Text(store.snapshot.lastTransactionDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Updated (store.snapshot.lastUpdated, style: .relative)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            Button("Add $5 Expense", systemImage: "minus.circle") {
                store.addExpense()
            }
            .buttonStyle(.borderedProminent)

            Button("Add $100 Income", systemImage: "plus.circle") {
                store.addIncome()
            }
            .buttonStyle(.bordered)

            Button("Test Notification", systemImage: "bell.badge") {
                Task { await store.testNotification() }
            }
            .buttonStyle(.bordered)
            .disabled(store.isWorking)

            Button("Test Apple Intelligence", systemImage: "apple.intelligence") {
                Task { await store.testAppleIntelligence() }
            }
            .buttonStyle(.bordered)
            .disabled(store.isWorking)

            Button("Refresh Widget", systemImage: "arrow.clockwise.circle") {
                store.refreshWidget()
            }
            .buttonStyle(.bordered)
            .gridCellColumns(2)
        }
        .labelStyle(.titleAndIcon)
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("Diagnostics", systemImage: "stethoscope")
            diagnosticRow(
                title: "Shared App Group",
                value: store.snapshot.appGroupStatusText,
                tint: store.snapshot.appGroupAvailable ? .green : .red
            )
            diagnosticRow(
                title: "Main app storage",
                value: store.snapshot.appGroupAvailable ? "WORKING" : "UNAVAILABLE",
                tint: store.snapshot.appGroupAvailable ? .green : .red
            )
            diagnosticRow(
                title: "Last widget update",
                value: formattedDate(store.snapshot.lastWidgetRefresh) ?? "Never requested",
                tint: .primary
            )
            diagnosticRow(title: "Current iOS", value: store.iosVersion, tint: .primary)
            Text("Widget and App Intent logs use separate contexts so shared-storage failures can be distinguished in device logs.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardSurface()
    }

    private var intelligenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("Foundation Models", systemImage: "apple.intelligence")
            diagnosticRow(title: "Availability", value: store.foundationModelStatus, tint: .primary)
            if let result = store.foundationModelResult {
                Text(result)
                    .font(.body)
                    .textSelection(.enabled)
            } else {
                Text("The test uses only Apple’s on-device model and makes no network request.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardSurface()
    }

    private var notificationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("Local Notifications", systemImage: "bell")
            Text(store.notificationStatus ?? "Tap Test Notification to request permission and schedule a notification in about 10 seconds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .cardSurface()
    }

    private func cardTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }

    private func diagnosticRow(title: String, value: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(tint)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private func formattedDate(_ date: Date?) -> String? {
        date?.formatted(date: .abbreviated, time: .shortened)
    }
}

private extension View {
    func cardSurface() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

