import SwiftUI

private enum PasscodeSheet: Identifiable, Equatable {
    case set
    case change

    var id: String {
        switch self {
        case .set:
            return "set"
        case .change:
            return "change"
        }
    }

    var title: String {
        switch self {
        case .set:
            return "Set app passcode"
        case .change:
            return "Change app passcode"
        }
    }
}

@MainActor
struct SecuritySettingsView: View {
    @ObservedObject var store: LedgerStore
    @ObservedObject var security: AppSecurityService
    @State private var passcodeSheet: PasscodeSheet?
    @State private var isShowingRemoveConfirmation = false
    @State private var isUpdatingBiometrics = false
    @State private var errorMessage: String?
    @State private var dailyReminderStatus: String?
    @State private var isUpdatingDailyReminder = false
    @AppStorage(PocketLedgerTheme.colorThemeKey) private var selectedColorTheme = PocketLedgerColorTheme.ocean.rawValue
    @AppStorage(PocketLedgerTheme.appearanceModeKey) private var selectedAppearanceMode = PocketLedgerAppearanceMode.system.rawValue
    @AppStorage(NotificationService.dailyTransactionReminderEnabledKey)
    private var isDailyTransactionReminderEnabled = false
    @AppStorage(NotificationService.dailyTransactionReminderMinutesKey)
    private var dailyTransactionReminderMinutes = NotificationService.dailyTransactionReminderDefaultMinutes

    var body: some View {
        Form {
                Section("Appearance") {
                    Picker("Mode", selection: $selectedAppearanceMode) {
                        ForEach(PocketLedgerAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    ForEach(PocketLedgerColorTheme.allCases) { theme in
                        Button {
                            selectedColorTheme = theme.rawValue
                        } label: {
                            HStack(spacing: 12) {
                                HStack(spacing: 4) {
                                    ForEach(theme.previewColors.indices, id: \.self) { index in
                                        Circle()
                                            .fill(theme.previewColors[index])
                                            .frame(width: 12, height: 12)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(theme.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(theme.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                                }

                                Spacer()

                                if selectedColorTheme == theme.rawValue {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(PocketLedgerTheme.accent)
                                }
                            }
                            .foregroundStyle(PocketLedgerTheme.textPrimary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Choose a palette and decide whether Pocket Ledger follows the device appearance or stays light or dark.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Reminders") {
                    Toggle(isOn: dailyReminderEnabledBinding) {
                        Label("Daily transaction reminder", systemImage: "bell.badge")
                    }
                    .disabled(isUpdatingDailyReminder)
                    .accessibilityIdentifier("daily-transaction-reminder-toggle")

                    DatePicker(
                        "Reminder time",
                        selection: dailyReminderTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(isUpdatingDailyReminder)
                    .accessibilityIdentifier("daily-transaction-reminder-time")

                    Text("Get a daily notification to add today’s transactions. Notification access is requested when you enable this reminder.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let dailyReminderStatus {
                        Text(dailyReminderStatus)
                            .font(.footnote)
                            .foregroundStyle(
                                dailyReminderStatus.contains("Allow notifications")
                                    ? PocketLedgerTheme.warning
                                    : PocketLedgerTheme.textSecondary
                            )
                    }
                }

                Section("App lock") {
                    if security.isPasscodeEnabled {
                        Label("Passcode enabled", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(PocketLedgerTheme.positive)

                        Button("Change passcode") {
                            passcodeSheet = .change
                        }

                        Button("Remove passcode", role: .destructive) {
                            isShowingRemoveConfirmation = true
                        }
                    } else {
                        Label("App lock is off", systemImage: "lock.open")
                            .foregroundStyle(.secondary)

                        Button {
                            passcodeSheet = .set
                        } label: {
                            Label("Set app passcode", systemImage: "lock.fill")
                        }
                    }

                    Text("Your passcode is stored as a salted verifier in the iPhone Keychain. It is not saved with your ledger data.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Biometric unlock") {
                    Toggle(isOn: biometricsBinding) {
                        Label(
                            "Unlock with \(security.biometricName)",
                            systemImage: security.availableBiometry?.systemImage ?? "touchid"
                        )
                    }
                    .disabled(
                        !security.isPasscodeEnabled
                            || security.availableBiometry == nil
                            || isUpdatingBiometrics
                    )

                    if !security.isPasscodeEnabled {
                        Text("Set an app passcode first. Biometrics unlocks the app passcode screen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if security.availableBiometry == nil {
                        Text("Set up Face ID or Touch ID in the device settings before enabling biometric unlock.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("You will confirm your identity once when enabling this option.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Privacy note") {
                    Text("Financial values in widgets and watch complications are marked private so the system can redact them on the Lock Screen and during Always On. Actions that change your ledger still require authentication.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Data") {
                    NavigationLink {
                        DataTransferView(store: store)
                    } label: {
                        Label("Import & Backup", systemImage: "arrow.down.doc")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .pocketScreen()
            .listRowBackground(Color.clear)
            .tint(PocketLedgerTheme.accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $passcodeSheet) { sheet in
                PasscodeSetupView(security: security, mode: sheet)
            }
            .confirmationDialog(
                "Remove your app passcode?",
                isPresented: $isShowingRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove passcode", role: .destructive, action: removePasscode)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The app will remain unlocked until you set a new passcode.")
            }
            .alert("Security setting not changed", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private var dailyReminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { isDailyTransactionReminderEnabled },
            set: { updateDailyTransactionReminder(isEnabled: $0) }
        )
    }

    private var dailyReminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: dailyTransactionReminderMinutes / 60,
                    minute: dailyTransactionReminderMinutes % 60,
                    second: 0,
                    of: .now
                ) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                dailyTransactionReminderMinutes = (components.hour ?? 20) * 60
                    + (components.minute ?? 0)
                if isDailyTransactionReminderEnabled {
                    updateDailyTransactionReminder(isEnabled: true)
                }
            }
        )
    }

    private func updateDailyTransactionReminder(isEnabled: Bool) {
        guard !isUpdatingDailyReminder else { return }
        isDailyTransactionReminderEnabled = isEnabled
        isUpdatingDailyReminder = true

        Task {
            defer { isUpdatingDailyReminder = false }
            if isEnabled {
                do {
                    try await NotificationService.enableDailyTransactionReminder(
                        minutesAfterMidnight: dailyTransactionReminderMinutes
                    )
                    dailyReminderStatus = "Daily transaction reminder is enabled."
                } catch {
                    isDailyTransactionReminderEnabled = false
                    dailyReminderStatus = error.localizedDescription
                }
            } else {
                NotificationService.disableDailyTransactionReminder()
                dailyReminderStatus = "Daily transaction reminder is off."
            }
        }
    }

    private var biometricsBinding: Binding<Bool> {
        Binding(
            get: { security.biometricsEnabled },
            set: { enabled in
                guard !isUpdatingBiometrics else { return }
                isUpdatingBiometrics = true
                Task {
                    do {
                        try await security.setBiometricsEnabled(enabled)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    isUpdatingBiometrics = false
                }
            }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func removePasscode() {
        do {
            try security.removePasscode()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
private struct PasscodeSetupView: View {
    @ObservedObject var security: AppSecurityService
    let mode: PasscodeSheet

    @Environment(\.dismiss) private var dismiss
    @State private var currentPasscode = ""
    @State private var newPasscode = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if mode == .change {
                    Section("Current passcode") {
                        passcodeField("Current passcode", text: $currentPasscode)
                    }
                }

                Section("New passcode") {
                    passcodeField("4 to 6 digits", text: $newPasscode)
                    passcodeField("Confirm passcode", text: $confirmation)
                }

                Section {
                    Label(
                        "The passcode is stored securely on this device and cannot be recovered if forgotten.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .pocketScreen()
            .listRowBackground(Color.clear)
            .tint(PocketLedgerTheme.accent)
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .alert("Passcode not saved", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func passcodeField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .keyboardType(.numberPad)
            .onChange(of: text.wrappedValue) { _, value in
                let sanitized = AppPasscodeRules.sanitized(value)
                if sanitized != value {
                    text.wrappedValue = sanitized
                }
            }
    }

    private var canSave: Bool {
        AppPasscodeRules.isValid(newPasscode)
            && newPasscode == confirmation
            && (mode == .set || AppPasscodeRules.isValid(currentPasscode))
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        guard AppPasscodeRules.isValid(newPasscode) else {
            errorMessage = "Use a passcode with 4 to 6 digits."
            return
        }
        guard newPasscode == confirmation else {
            errorMessage = "The passcodes do not match."
            return
        }
        if mode == .change && !security.verifyPasscode(currentPasscode) {
            errorMessage = "The current passcode is incorrect."
            return
        }

        do {
            try security.setPasscode(newPasscode)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
struct AppLockView: View {
    @ObservedObject var security: AppSecurityService
    @Binding var isUnlocked: Bool

    @Environment(\.scenePhase) private var scenePhase
    @State private var passcode = ""
    @State private var errorMessage: String?
    @State private var isAuthenticating = false
    @State private var shouldRetryBiometricsOnActivation = false

    var body: some View {
        ZStack {
            PocketLedgerTheme.background
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(PocketLedgerTheme.accent)

                VStack(spacing: 8) {
                    Text("Pocket Ledger is locked")
                        .font(.title2.weight(.bold))
                    Text("Enter your app passcode to view your financial data.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                SecureField("App passcode", text: $passcode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    .onChange(of: passcode) { _, value in
                        let sanitized = AppPasscodeRules.sanitized(value)
                        if sanitized != value {
                            passcode = sanitized
                        }
                    }

                Button("Unlock", action: unlockWithPasscode)
                    .buttonStyle(.glassProminent)
                    .tint(PocketLedgerTheme.accent)
                    .disabled(!AppPasscodeRules.isValid(passcode))

                if security.biometricsEnabled {
                    Button {
                        Task { await unlockWithBiometrics() }
                    } label: {
                        Label(
                            "Unlock with \(security.biometricName)",
                            systemImage: security.availableBiometry?.systemImage ?? "touchid"
                        )
                    }
                    .disabled(isAuthenticating)
                }

                if isAuthenticating {
                    ProgressView()
                        .controlSize(.small)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(PocketLedgerTheme.accent)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(PocketLedgerTheme.textPrimary)
        .tint(PocketLedgerTheme.accent)
        .preferredColorScheme(PocketLedgerTheme.appearanceMode.preferredColorScheme)
        .onAppear {
            requestBiometricUnlockIfPossible()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                shouldRetryBiometricsOnActivation = true
            } else if phase == .active, shouldRetryBiometricsOnActivation {
                shouldRetryBiometricsOnActivation = false
                requestBiometricUnlockIfPossible()
            }
        }
    }

    private func requestBiometricUnlockIfPossible() {
        guard scenePhase == .active, !isUnlocked, !isAuthenticating else { return }
        Task {
            await unlockWithBiometrics()
        }
    }

    private func unlockWithPasscode() {
        guard security.verifyPasscode(passcode) else {
            passcode = ""
            errorMessage = "That passcode is incorrect."
            return
        }

        errorMessage = nil
        isUnlocked = true
    }

    private func unlockWithBiometrics() async {
        guard security.biometricsEnabled, !isAuthenticating else { return }

        isAuthenticating = true
        let authenticated = await security.authenticateWithBiometrics()
        isAuthenticating = false

        if authenticated, scenePhase != .background {
            errorMessage = nil
            isUnlocked = true
        } else if !Task.isCancelled, scenePhase != .background {
            errorMessage = "Biometric unlock was not completed. Enter your app passcode to continue."
        }
    }
}
