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
    @ObservedObject var security: AppSecurityService
    @State private var passcodeSheet: PasscodeSheet?
    @State private var isShowingRemoveConfirmation = false
    @State private var isUpdatingBiometrics = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
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
                    Text("This lock protects the Pocket Ledger app. Widgets are separate system surfaces and may continue to show their configured balance.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PocketLedgerTheme.background)
            .listRowBackground(PocketLedgerTheme.surface)
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
            .background(PocketLedgerTheme.background)
            .listRowBackground(PocketLedgerTheme.surface)
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

    @State private var passcode = ""
    @State private var errorMessage: String?
    @State private var isAuthenticating = false

    var body: some View {
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
                .buttonStyle(.borderedProminent)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pocketScreen()
        .task {
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

        if authenticated {
            errorMessage = nil
            isUnlocked = true
        } else if !Task.isCancelled {
            errorMessage = "Biometric unlock was not completed. Enter your app passcode to continue."
        }
    }
}
