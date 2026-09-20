import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct DataTransferView: View {
    @ObservedObject var store: LedgerStore

    @State private var isShowingImporter = false
    @State private var isExportingBackup = false
    @State private var isExportingBackupBundle = false
    @State private var isExportingCSV = false
    @State private var backupDocument = PocketLedgerBackupDocument(data: Data())
    @State private var backupBundleDocument = PocketLedgerBackupBundleDocument(data: Data())
    @State private var csvDocument = LedgerCSVDocument(data: Data())
    @State private var pendingBackup: BackupImportCandidate?
    @State private var pendingDocument: ImportedDocument?
    @State private var errorMessage: String?
    @State private var isShowingResetPreparation = false
    @State private var isShowingResetWarning = false
    @State private var isShowingFinalResetWarning = false
    @State private var isContinuingToResetAfterBackup = false
    @State private var isShowingResetSuccess = false
    @State private var isShowingRecoveryConfirmation = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                introCard
                backupCard
                if store.hasRecoverySnapshot {
                    recoveryCard
                }
                importCard
                resetCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .pocketScreen()
        .navigationTitle("Import & Backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false,
            onCompletion: importFile
        )
        .fileExporter(
            isPresented: $isExportingBackup,
            document: backupDocument,
            contentType: .json,
            defaultFilename: "Pocket-Ledger-backup",
            onCompletion: exportCompleted
        )
        .fileExporter(
            isPresented: $isExportingBackupBundle,
            document: backupBundleDocument,
            contentType: .data,
            defaultFilename: "Pocket-Ledger-backup.pocketledger",
            onCompletion: exportCompleted
        )
        .fileExporter(
            isPresented: $isExportingCSV,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "Pocket-Ledger-transactions",
            onCompletion: exportCompleted
        )
        .sheet(item: $pendingBackup) { candidate in
            BackupRestoreView(store: store, candidate: candidate)
        }
        .sheet(item: $pendingDocument) { document in
            ImportWizardView(store: store, document: document)
                .presentationDetents([.large])
        }
        .confirmationDialog(
            "Back up before erasing?",
            isPresented: $isShowingResetPreparation,
            titleVisibility: .visible
        ) {
            Button("Export backup, then continue") {
                startBackupExport(continueToReset: true)
            }
            Button("Continue without backup", role: .destructive) {
                isShowingResetWarning = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A full Pocket Ledger backup is the safest way to restore this ledger after it is erased.")
        }
        .confirmationDialog(
            "Erase all ledger data?",
            isPresented: $isShowingResetWarning,
            titleVisibility: .visible
        ) {
            Button("Show final warning", role: .destructive) {
                isShowingFinalResetWarning = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every account, category, transaction, scheduled transaction, and exchange rate from this device. The action cannot be undone without a backup.")
        }
        .alert("Final warning: erase everything?", isPresented: $isShowingFinalResetWarning) {
            Button("Erase all data", role: .destructive, action: resetLedger)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is the last confirmation. Your ledger will be replaced with an empty one immediately.")
        }
        .alert("Ledger erased", isPresented: $isShowingResetSuccess) {
            Button("OK") {}
        } message: {
            Text("Your Pocket Ledger data is now empty. App lock and appearance settings were kept.")
        }
        .confirmationDialog(
            "Restore the last-good ledger?",
            isPresented: $isShowingRecoveryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore last-good snapshot", action: restoreLastGoodSnapshot)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces the current ledger with the snapshot captured before the last destructive restore.")
        }
        .alert("Data transfer failed", isPresented: errorPresented) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Move your ledger safely", systemImage: "arrow.left.arrow.right")
                .font(.title3.weight(.bold))

            Text("Pocket Ledger can restore its own lossless backup or import rows from another app. Files are read on this device and are never uploaded.")
                .font(.subheadline)
                .foregroundStyle(PocketLedgerTheme.textSecondary)
        }
        .pocketCard()
    }

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pocket Ledger backup", systemImage: "externaldrive")
                .font(.title3.weight(.bold))

            Text("Full backups keep accounts, categories, transactions, schedules, and local receipt attachments so they can be restored later.")
                .font(.subheadline)
                .foregroundStyle(PocketLedgerTheme.textSecondary)

            Button {
                startBackupExport()
            } label: {
                Label("Export full backup", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(.glassProminent)

            Button {
                startJSONBackupExport()
            } label: {
                Label("Export JSON compatibility backup", systemImage: "doc.text")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)

            Button {
                csvDocument = LedgerCSVDocument(data: LedgerCSVExporter.data(for: store.data))
                isExportingCSV = true
            } label: {
                Label("Export transactions as CSV", systemImage: "tablecells")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)

            Text("The full backup includes local receipt files. JSON remains available for compatibility, while CSV is useful for spreadsheets and other finance apps.")
                .font(.footnote)
                .foregroundStyle(PocketLedgerTheme.textTertiary)
        }
        .pocketCard()
    }

    private var resetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Erase ledger data", systemImage: "trash")
                .font(.title3.weight(.bold))
                .foregroundStyle(PocketLedgerTheme.warning)

            Text("Reset removes all ledger accounts, categories, transactions, schedules, and saved exchange rates. Your app lock and appearance settings stay unchanged.")
                .font(.subheadline)
                .foregroundStyle(PocketLedgerTheme.textSecondary)

            Button("Review reset warnings", role: .destructive) {
                isShowingResetPreparation = true
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.glass)
            .tint(PocketLedgerTheme.warning)
        }
        .pocketCard()
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Last-good recovery snapshot", systemImage: "arrow.uturn.backward.circle")
                .font(.title3.weight(.bold))

            Text("Pocket Ledger keeps a local recovery copy before replacing the ledger. It includes receipt files when they are still available.")
                .font(.subheadline)
                .foregroundStyle(PocketLedgerTheme.textSecondary)

            Button {
                isShowingRecoveryConfirmation = true
            } label: {
                Label("Restore last-good snapshot", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .tint(PocketLedgerTheme.accent)
        }
        .pocketCard()
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Import from another app", systemImage: "arrow.down.doc")
                .font(.title3.weight(.bold))

            Text("Choose a CSV, TSV, JSON, Excel workbook, or SQLite backup such as Money Manager's .mmbak file. The next screen lets you select a table and map its columns.")
                .font(.subheadline)
                .foregroundStyle(PocketLedgerTheme.textSecondary)

            Button {
                isShowingImporter = true
            } label: {
                Label("Choose import file", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(.glassProminent)

            Text("Supported spreadsheet input is .xlsx. Legacy binary .xls files should be exported as .xlsx, CSV, or TSV first.")
                .font(.footnote)
                .foregroundStyle(PocketLedgerTheme.textTertiary)
        }
        .pocketCard()
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            if let bundle = try? LedgerBackupCodec.decodeBundle(data) {
                pendingBackup = BackupImportCandidate(
                    fileName: url.lastPathComponent,
                    backup: PocketLedgerBackup(data: bundle.data, exportedAt: bundle.exportedAt),
                    attachmentFiles: Dictionary(uniqueKeysWithValues: bundle.attachments.map { ($0.id, $0.data) })
                )
            } else if let backup = try? LedgerBackupCodec.decode(data) {
                pendingBackup = BackupImportCandidate(
                    fileName: url.lastPathComponent,
                    backup: backup,
                    attachmentFiles: [:]
                )
            } else {
                pendingDocument = try FinanceImportParser.parse(url: url, data: data)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreLastGoodSnapshot() {
        guard store.restoreLastGoodSnapshot() else {
            errorMessage = store.lastActionStatus ?? "The recovery snapshot could not be restored."
            return
        }
    }

    private func exportCompleted(_ result: Result<URL, Error>) {
        let shouldContinueToReset = isContinuingToResetAfterBackup
        isContinuingToResetAfterBackup = false

        switch result {
        case .success:
            if shouldContinueToReset {
                isShowingResetWarning = true
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func startBackupExport(continueToReset: Bool = false) {
        do {
            backupBundleDocument = PocketLedgerBackupBundleDocument(
                data: try LedgerBackupCodec.encodeBundle(
                    store.data,
                    attachmentData: store.attachmentFiles()
                )
            )
            isContinuingToResetAfterBackup = continueToReset
            isExportingBackupBundle = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startJSONBackupExport() {
        do {
            backupDocument = PocketLedgerBackupDocument(data: try LedgerBackupCodec.encode(store.data))
            isExportingBackup = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetLedger() {
        guard store.resetLedger() else {
            errorMessage = store.lastActionStatus ?? "The ledger could not be reset."
            return
        }
        isShowingResetSuccess = true
    }
}

private struct BackupImportCandidate: Identifiable {
    let id = UUID()
    let fileName: String
    let backup: PocketLedgerBackup
    let attachmentFiles: [UUID: Data]
}

@MainActor
private struct BackupRestoreView: View {
    @ObservedObject var store: LedgerStore
    let candidate: BackupImportCandidate

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingReplaceConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Backup") {
                    LabeledContent("File", value: candidate.fileName)
                    LabeledContent("Created", value: candidate.backup.exportedAt.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))
                    LabeledContent("Accounts", value: "\(candidate.backup.data.accounts.count)")
                    LabeledContent("Categories", value: "\(candidate.backup.data.categories.count)")
                    LabeledContent("Transactions", value: "\(candidate.backup.data.transactions.count)")
                    if !candidate.backup.data.attachments.isEmpty {
                        LabeledContent("Attachments", value: "\(candidate.backup.data.attachments.count)")
                        if candidate.attachmentFiles.count < candidate.backup.data.attachments.count {
                            Text("Some attachment bytes are missing from this compatibility backup. The ledger will restore, but those files will show as unavailable.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Merge into current ledger", action: merge)

                    Button("Replace current ledger", role: .destructive) {
                        isShowingReplaceConfirmation = true
                    }
                } footer: {
                    Text("Merge keeps existing records and adds records with new IDs. Replace removes the current ledger and restores this backup exactly.")
                }
            }
            .scrollContentBackground(.hidden)
            .pocketScreen()
            .listRowBackground(Color.clear)
            .tint(PocketLedgerTheme.accent)
            .navigationTitle("Restore backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                "Replace the current ledger?",
                isPresented: $isShowingReplaceConfirmation,
                titleVisibility: .visible
            ) {
                Button("Replace ledger", role: .destructive, action: replace)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The current accounts, categories, and transactions will be replaced by the backup.")
            }
            .alert("Restore failed", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func merge() {
        guard store.mergeData(
            candidate.backup.data,
            attachmentFiles: candidate.attachmentFiles
        ) else {
            errorMessage = store.lastActionStatus ?? "The backup could not be saved."
            return
        }
        dismiss()
    }

    private func replace() {
        guard store.replaceData(
            candidate.backup.data,
            attachmentFiles: candidate.attachmentFiles
        ) else {
            errorMessage = store.lastActionStatus ?? "The backup could not be saved."
            return
        }
        dismiss()
    }
}
