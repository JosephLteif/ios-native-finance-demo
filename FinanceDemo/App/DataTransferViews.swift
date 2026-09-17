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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                introCard
                backupCard
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
            ImportMappingView(store: store, document: document)
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
            .buttonStyle(.borderedProminent)

            Button {
                startJSONBackupExport()
            } label: {
                Label("Export JSON compatibility backup", systemImage: "doc.text")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                csvDocument = LedgerCSVDocument(data: LedgerCSVExporter.data(for: store.data))
                isExportingCSV = true
            } label: {
                Label("Export transactions as CSV", systemImage: "tablecells")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

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
            .buttonStyle(.bordered)
            .tint(PocketLedgerTheme.warning)
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
            .buttonStyle(.borderedProminent)

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
            .background(PocketLedgerTheme.background)
            .listRowBackground(PocketLedgerTheme.surface)
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

@MainActor
private struct ImportMappingView: View {
    @ObservedObject var store: LedgerStore
    let document: ImportedDocument

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTableID: String
    @State private var mapping: [ImportField: String?]
    @State private var defaultKind: TransactionKind = .expense
    @State private var defaultCurrency: LedgerCurrency = .usd
    @State private var defaultAccountID: UUID?
    @State private var defaultDestinationAccountID: UUID?
    @State private var createMissingAccounts = true
    @State private var createMissingCategories = true
    @State private var errorMessage: String?
    @State private var successMessage: String?

    init(store: LedgerStore, document: ImportedDocument) {
        _store = ObservedObject(wrappedValue: store)
        self.document = document
        let table = document.tables[0]
        _selectedTableID = State(initialValue: table.id)
        _mapping = State(initialValue: FinanceImportParser.suggestedMapping(columns: table.columns))
        _defaultAccountID = State(initialValue: store.activeAccounts.first?.id)
        _defaultDestinationAccountID = State(
            initialValue: store.activeAccounts.dropFirst().first?.id ?? store.activeAccounts.first?.id
        )
    }

    private var selectedTable: ImportedTable {
        document.tables.first(where: { $0.id == selectedTableID }) ?? document.tables[0]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    LabeledContent("File", value: document.fileName)
                    LabeledContent("Format", value: document.format.displayName)

                    if document.tables.count > 1 {
                        Picker("Table", selection: $selectedTableID) {
                            ForEach(document.tables) { table in
                                Text(table.name).tag(table.id)
                            }
                        }
                    }

                    Text("\(selectedTable.rows.count) rows · \(selectedTable.columns.count) columns")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(ImportField.allCases) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            Picker(field.displayName, selection: mappingBinding(for: field)) {
                                Text("Not mapped").tag(String?.none)
                                ForEach(selectedTable.columns, id: \.self) { column in
                                    Text(column).tag(Optional(column))
                                }
                            }
                            Text(field.helpText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Map fields")
                } footer: {
                    Text("Date and Amount are required. The other mappings are optional when you choose defaults below.")
                }

                Section("Defaults") {
                    Picker("Default type", selection: $defaultKind) {
                        ForEach(TransactionKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }

                    Picker("Default currency", selection: $defaultCurrency) {
                        ForEach(LedgerCurrency.allCases) { currency in
                            Text(currency.rawValue).tag(currency)
                        }
                    }

                    Picker("Default account", selection: $defaultAccountID) {
                        Text("Use mapped account").tag(UUID?.none)
                        ForEach(store.activeAccounts) { account in
                            Text("\(account.name) · \(account.currency.rawValue)").tag(Optional(account.id))
                        }
                    }

                    Picker("Default destination", selection: $defaultDestinationAccountID) {
                        Text("Use mapped destination").tag(UUID?.none)
                        ForEach(store.activeAccounts) { account in
                            Text("\(account.name) · \(account.currency.rawValue)").tag(Optional(account.id))
                        }
                    }

                    Toggle("Create missing accounts", isOn: $createMissingAccounts)
                    Toggle("Create missing categories", isOn: $createMissingCategories)
                }

                Section("Preview") {
                    ForEach(Array(selectedTable.rows.prefix(5).enumerated()), id: \.offset) { index, row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Row \(index + 2)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PocketLedgerTheme.accent)
                            Text(row.filter { !$0.isEmpty }.prefix(5).joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(PocketLedgerTheme.background)
            .listRowBackground(PocketLedgerTheme.surface)
            .tint(PocketLedgerTheme.accent)
            .navigationTitle("Map import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: importRows)
                        .disabled(!isReadyToImport)
                }
            }
            .onChange(of: selectedTableID) { _, newValue in
                guard let table = document.tables.first(where: { $0.id == newValue }) else { return }
                mapping = FinanceImportParser.suggestedMapping(columns: table.columns)
            }
            .alert("Import completed", isPresented: successPresented) {
                Button("Done") { dismiss() }
            } message: {
                Text(successMessage ?? "")
            }
            .alert("Import failed", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var isReadyToImport: Bool {
        isMapped(.date) && isMapped(.amount)
    }

    private func isMapped(_ field: ImportField) -> Bool {
        guard let value = mapping[field] else { return false }
        return value != nil
    }

    private func mappingBinding(for field: ImportField) -> Binding<String?> {
        Binding(
            get: { mapping[field] ?? nil },
            set: { mapping[field] = $0 }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var successPresented: Binding<Bool> {
        Binding(
            get: { successMessage != nil },
            set: { if !$0 { successMessage = nil } }
        )
    }

    private func importRows() {
        let options = ImportOptions(
            defaultKind: defaultKind,
            defaultCurrency: defaultCurrency,
            defaultAccountID: defaultAccountID,
            defaultDestinationAccountID: defaultDestinationAccountID,
            createMissingAccounts: createMissingAccounts,
            createMissingCategories: createMissingCategories
        )

        do {
            let result = try FinanceImportBuilder.build(
                table: selectedTable,
                mapping: mapping,
                options: options,
                existing: store.data
            )
            guard store.mergeData(result.data) else {
                errorMessage = store.lastActionStatus ?? "The imported rows could not be saved."
                return
            }

            var message = "Imported \(result.importedRows) rows."
            if result.skippedRows > 0 {
                message += " Skipped \(result.skippedRows) rows."
                if !result.warnings.isEmpty {
                    message += "\n\n" + result.warnings.prefix(3).joined(separator: "\n")
                }
            }
            successMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
