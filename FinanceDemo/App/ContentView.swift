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
                    capabilitiesCard
                    diagnosticsCard
                    intelligenceCard
                    shortcutsCard
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
            Text("Finance Demo")
                .font(.title2.weight(.semibold))
            Text(store.snapshot.balanceText)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .accessibilityIdentifier("demo-balance")
            Text(store.snapshot.lastTransactionDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text("Updated")
                Text(store.snapshot.lastUpdated, style: .relative)
            }
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

            Button("Reset Demo", systemImage: "arrow.counterclockwise.circle") {
                store.resetDemo()
            }
            .buttonStyle(.bordered)

            Button("Refresh Widget", systemImage: "arrow.clockwise.circle") {
                store.refreshWidget()
            }
            .buttonStyle(.bordered)
            .gridCellColumns(2)

            if let status = store.lastActionStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .gridCellColumns(2)
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private var capabilitiesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("Capabilities", systemImage: "sparkles.rectangle.stack")
            diagnosticRow(
                title: "WidgetKit",
                value: store.snapshot.appGroupAvailable ? "Ready" : "Needs App Group signing",
                tint: store.snapshot.appGroupAvailable ? .green : .orange
            )
            diagnosticRow(title: "App Intents", value: "5 actions", tint: .green)
            diagnosticRow(title: "Siri / Shortcuts", value: "5 shortcuts", tint: .green)
            diagnosticRow(title: "Apple Intelligence", value: store.foundationModelStatus, tint: .primary)
            diagnosticRow(title: "Local notifications", value: "Available", tint: .green)
            Text("The widget needs a valid App Group signature. Siri, Shortcuts, notifications, and Apple Intelligence can be tested independently.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardSurface()
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
                value: mainStorageStatusText,
                tint: store.snapshot.appStorageAvailable ? .green : .red
            )
            diagnosticRow(
                title: "Last widget update",
                value: formattedDate(store.snapshot.lastWidgetRefresh) ?? "Never requested",
                tint: .primary
            )
            diagnosticRow(title: "Current iOS", value: store.iosVersion, tint: .primary)
            Text("The app and Siri can use local app storage when App Group signing is unavailable; widgets still require the shared App Group.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardSurface()
    }

    private var intelligenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("Foundation Models", systemImage: "apple.intelligence")
            diagnosticRow(title: "Availability", value: store.foundationModelStatus, tint: .primary)
            if let input = store.foundationModelInput {
                diagnosticRow(title: "Input balance", value: input, tint: .primary)
            }
            if let result = store.foundationModelResult {
                Text(result)
                    .font(.body)
                    .textSelection(.enabled)
            } else {
                Text("The test uses the current balance and latest transaction with Apple’s on-device model. It makes no network request.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardSurface()
    }

    private var shortcutsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("Siri & Shortcuts", systemImage: "waveform")
            Text("These App Shortcuts are registered automatically. Say the phrase with the app name, for example: “Get my demo balance in Finance Demo.”")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            shortcutRow("Get my finance demo balance")
            shortcutRow("Add a five dollar expense")
            shortcutRow("Add a hundred dollars of income")
            shortcutRow("Reset my finance demo")
            shortcutRow("Summarize my demo budget")
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

    private func shortcutRow(_ phrase: String) -> some View {
        Label(phrase, systemImage: "mic")
            .font(.subheadline)
    }

    private var mainStorageStatusText: String {
        if store.snapshot.appGroupAvailable {
            return "WORKING"
        }
        return store.snapshot.appStorageAvailable ? "LOCAL FALLBACK" : "UNAVAILABLE"
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
