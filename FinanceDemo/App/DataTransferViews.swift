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
            .buttonStyle(.bordered)
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
    @State private var reviewCandidate: ImportReviewCandidate?
    @State private var isPreparingReview = false

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

                    Text("The next screen reviews every parsed row before anything is saved. When available, on-device Apple Intelligence classifies all imported account names in one pass. If it is unavailable, mapped values, existing accounts, and account-name hints provide the fallback.")
                        .font(.footnote)
                        .foregroundStyle(PocketLedgerTheme.textTertiary)
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
                    Button(isPreparingReview ? "Preparing…" : "Review import", action: reviewImport)
                        .disabled(!isReadyToImport || isPreparingReview)
                }
            }
            .onChange(of: selectedTableID) { _, newValue in
                guard let table = document.tables.first(where: { $0.id == newValue }) else { return }
                mapping = FinanceImportParser.suggestedMapping(columns: table.columns)
            }
            .alert("Import failed", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(item: $reviewCandidate) { candidate in
                ImportReviewView(store: store, candidate: candidate) {
                    dismiss()
                }
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

    private func reviewImport() {
        guard !isPreparingReview else { return }
        isPreparingReview = true

        let table = selectedTable
        let currentMapping = mapping
        let accountCandidates = FinanceImportBuilder.accountImportCandidates(
            table: table,
            mapping: currentMapping
        )

        Task { @MainActor in
            defer { isPreparingReview = false }

            let accountMapping = await FoundationModelService.classifyImportAccounts(accountCandidates)
            guard !Task.isCancelled else { return }

            let options = ImportOptions(
                defaultKind: defaultKind,
                defaultCurrency: defaultCurrency,
                defaultAccountID: defaultAccountID,
                defaultDestinationAccountID: defaultDestinationAccountID,
                // Missing records are provisional until the review is confirmed. This keeps
                // rows available so the user can map them to an existing record first.
                createMissingAccounts: true,
                createMissingCategories: true,
                accountSuggestions: accountMapping.suggestions
            )

            do {
                let builtResult = try FinanceImportBuilder.build(
                    table: table,
                    mapping: currentMapping,
                    options: options,
                    existing: store.data
                )
                var warnings = builtResult.warnings
                if let warning = accountMapping.warning {
                    warnings.insert(warning, at: 0)
                }
                let result = FinanceImportResult(
                    data: builtResult.data,
                    importedRows: builtResult.importedRows,
                    skippedRows: builtResult.skippedRows,
                    warnings: warnings
                )
                reviewCandidate = ImportReviewCandidate(
                    fileName: document.fileName,
                    tableName: table.name,
                    result: result,
                    createMissingAccounts: createMissingAccounts,
                    createMissingCategories: createMissingCategories
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ImportReviewCandidate: Identifiable {
    let id = UUID()
    let fileName: String
    let tableName: String
    let result: FinanceImportResult
    let createMissingAccounts: Bool
    let createMissingCategories: Bool
}

@MainActor
private struct ImportReviewView: View {
    @ObservedObject var store: LedgerStore
    let candidate: ImportReviewCandidate
    let onImported: () -> Void
    private let duplicateTransactionIDs: Set<UUID>

    @Environment(\.dismiss) private var dismiss
    @State private var importedData: FinanceData
    @State private var excludedDuplicateIDs: Set<UUID>
    @State private var searchText = ""
    @State private var isShowingConfirmation = false
    @State private var errorMessage: String?

    init(
        store: LedgerStore,
        candidate: ImportReviewCandidate,
        onImported: @escaping () -> Void
    ) {
        _store = ObservedObject(wrappedValue: store)
        self.candidate = candidate
        self.onImported = onImported
        self.duplicateTransactionIDs = FinanceImportReview.duplicateTransactionIDs(
            in: candidate.result.data,
            existing: store.data
        )
        _importedData = State(initialValue: candidate.result.data)
        _excludedDuplicateIDs = State(
            initialValue: self.duplicateTransactionIDs
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Review before importing") {
                    LabeledContent("File", value: candidate.fileName)
                    LabeledContent("Table", value: candidate.tableName)
                    LabeledContent("Ready to import", value: importedRowCountLabel)
                    if candidate.result.skippedRows > 0 {
                        LabeledContent("Skipped while parsing", value: skippedRowCountLabel)
                    }
                    Text("Nothing has been saved yet. Assign accounts and categories below, then confirm the import.")
                        .font(.footnote)
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                }

                if !duplicateTransactionIDs.isEmpty {
                    Section("Possible duplicates") {
                        Text("These imported rows match transactions already in your ledger. They start excluded; turn one on if it should be imported again.")
                            .font(.footnote)
                            .foregroundStyle(PocketLedgerTheme.textSecondary)

                        ForEach(duplicateTransactionIDs.sorted { $0.uuidString < $1.uuidString }, id: \.self) { transactionID in
                            if let transaction = importedData.transactions.first(where: { $0.id == transactionID }) {
                                Toggle(isOn: keepDuplicateBinding(for: transactionID)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(transaction.note)
                                            .font(.subheadline.weight(.semibold))
                                        Text(duplicateSummary(for: transaction))
                                            .font(.caption)
                                            .foregroundStyle(PocketLedgerTheme.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if !importedData.accounts.isEmpty {
                    ImportReviewAccountsSection(accounts: $importedData.accounts) { accountID, oldCurrency, newCurrency in
                        importedData = FinanceAccountCurrencyMigration.migrating(
                            importedData,
                            accountID: accountID,
                            from: oldCurrency,
                            to: newCurrency
                        )
                    }
                }

                if !importedData.categories.isEmpty {
                    ImportReviewCategoriesSection(
                        categories: importedData.categories,
                        allCategories: availableCategories
                    )
                }

                ImportReviewTransactionsSection(
                    transactions: $importedData.transactions,
                    indices: filteredTransactionIndices,
                    accounts: availableAccounts,
                    categories: availableCategories
                )

                if !candidate.result.warnings.isEmpty {
                    Section("Warnings") {
                        ForEach(candidate.result.warnings, id: \.self) { warning in
                            Text(warning)
                                .font(.footnote)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(PocketLedgerTheme.background)
            .listRowBackground(PocketLedgerTheme.surface)
            .tint(PocketLedgerTheme.accent)
            .searchable(text: $searchText, prompt: "Search imported rows")
            .navigationTitle("Review import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(includedTransactions.count)") {
                        isShowingConfirmation = true
                    }
                }
            }
            .confirmationDialog(
                "Import these transactions?",
                isPresented: $isShowingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Import rows", action: importRows)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The reviewed accounts, categories, and transactions will be merged into your current ledger.")
            }
            .alert("Import failed", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var availableAccounts: [Account] {
        var accounts = store.data.accounts
        for account in importedData.accounts where !accounts.contains(where: { $0.id == account.id }) {
            accounts.append(account)
        }
        return accounts
    }

    private var availableCategories: [LedgerCategory] {
        var categories = store.data.categories
        for category in importedData.categories where !categories.contains(where: { $0.id == category.id }) {
            categories.append(category)
        }
        return categories
    }

    private var includedTransactions: [LedgerTransaction] {
        importedData.transactions.filter { !excludedDuplicateIDs.contains($0.id) }
    }

    private var filteredTransactionIndices: [Int] {
        importedData.transactions.indices.filter { index in
            guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
            let transaction = importedData.transactions[index]
            let accountText = (transaction.outflows + transaction.inflows)
                .compactMap { movement in availableAccounts.first(where: { $0.id == movement.accountID })?.name }
                .joined(separator: " ")
            let categoryText = categoryPath(for: transaction.categoryID)
            let amountText = (transaction.outflows.first?.money ?? transaction.inflows.first?.money)?.formatted ?? ""
            let haystack = [transaction.note, accountText, categoryText, amountText]
                .joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var importedRowCountLabel: String {
        String(includedTransactions.count) + " rows"
    }

    private var skippedRowCountLabel: String {
        String(candidate.result.skippedRows) + " rows"
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func keepDuplicateBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { !excludedDuplicateIDs.contains(id) },
            set: { keep in
                if keep {
                    excludedDuplicateIDs.remove(id)
                } else {
                    excludedDuplicateIDs.insert(id)
                }
            }
        )
    }

    private func duplicateSummary(for transaction: LedgerTransaction) -> String {
        let amount = (transaction.outflows.first?.money ?? transaction.inflows.first?.money)?.formatted ?? "—"
        return "\(transaction.date.formatted(.dateTime.month(.abbreviated).day().year())) · \(amount)"
    }

    private func categoryPath(for categoryID: UUID?) -> String {
        guard let categoryID else { return "Uncategorized" }

        var names: [String] = []
        var currentID: UUID? = categoryID
        var visited: Set<UUID> = []
        while let id = currentID,
              visited.insert(id).inserted,
              let category = availableCategories.first(where: { $0.id == id }) {
            names.append(category.name)
            currentID = category.parentID
        }
        return names.reversed().joined(separator: " / ")
    }

    private func importRows() {
        guard !includedTransactions.isEmpty else {
            errorMessage = "Keep at least one row before importing."
            return
        }
        var selectedData = importedData
        selectedData.transactions = includedTransactions
        let prepared = FinanceImportReview.removingUnusedCreatedRecords(from: selectedData)
        if !candidate.createMissingAccounts && !prepared.accounts.isEmpty {
            errorMessage = "Map the remaining new accounts to existing accounts, or enable account creation before importing."
            return
        }
        if !candidate.createMissingCategories && !prepared.categories.isEmpty {
            errorMessage = "Map the remaining new categories to existing categories, or enable category creation before importing."
            return
        }
        guard store.mergeData(prepared) else {
            errorMessage = store.lastActionStatus ?? "The imported rows could not be saved."
            return
        }
        onImported()
        dismiss()
    }
}

private struct ImportReviewAccountsSection: View {
    @Binding var accounts: [Account]
    let onCurrencyChange: (UUID, LedgerCurrency, LedgerCurrency) -> Void

    var body: some View {
        Section(
            content: {
                ForEach(accounts.indices, id: \.self) { index in
                    ImportReviewAccountRow(
                        account: $accounts[index],
                        onCurrencyChange: onCurrencyChange
                    )
                }
            },
            header: {
                Text("Accounts that may be created")
            },
            footer: {
                Text("The import attempts one on-device AI pass for all account names when available. Explicit mapped values and existing accounts take precedence; otherwise deterministic account-name hints and import defaults are used. You can change either value before importing. If you assign rows to existing accounts, unused provisional accounts will not be created.")
            }
        )
    }
}

private struct ImportReviewCategoriesSection: View {
    let categories: [LedgerCategory]
    let allCategories: [LedgerCategory]

    var body: some View {
        Section(
            content: {
                ForEach(categories) { category in
                    Label(categoryPath(for: category.id), systemImage: category.systemImage)
                }
            },
            header: {
                Text("Categories that may be created")
            },
            footer: {
                Text("Use the category picker on each row to keep, change, or remove a provisional category.")
            }
        )
    }

    private func categoryPath(for categoryID: UUID) -> String {
        var names: [String] = []
        var currentID: UUID? = categoryID
        var visited: Set<UUID> = []

        while let id = currentID,
              visited.insert(id).inserted,
              let category = allCategories.first(where: { $0.id == id }) {
            names.append(category.name)
            currentID = category.parentID
        }

        return names.reversed().joined(separator: " / ")
    }
}

private struct ImportReviewTransactionsSection: View {
    @Binding var transactions: [LedgerTransaction]
    let indices: [Int]
    let accounts: [Account]
    let categories: [LedgerCategory]

    var body: some View {
        Section(
            content: {
                if indices.isEmpty {
                    Text("No matching transactions")
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                } else {
                    ForEach(indices, id: \.self) { index in
                        ImportReviewTransactionRow(
                            transaction: transactionBinding(at: index),
                            rowNumber: index + 1,
                            accounts: accounts,
                            categories: categories
                        )
                    }
                }
            },
            header: {
                Text("Imported transactions")
            },
            footer: {
                Text("Search by note, account, category, or amount. Changes stay local until you tap Import.")
            }
        )
    }

    private func transactionBinding(at index: Int) -> Binding<LedgerTransaction> {
        Binding(
            get: { transactions[index] },
            set: { transactions[index] = $0 }
        )
    }
}

private struct ImportReviewAccountRow: View {
    @Binding var account: Account
    let onCurrencyChange: (UUID, LedgerCurrency, LedgerCurrency) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "\(account.name) · \(account.currency.rawValue)",
                systemImage: account.type.systemImage
            )
            .font(.subheadline.weight(.semibold))

            Picker("Account type", selection: $account.type) {
                ForEach(AccountType.allCases, id: \.self) { type in
                    Text(verbatim: type.displayName)
                        .tag(type)
                }
            }

            Picker("Currency", selection: $account.currency) {
                ForEach(LedgerCurrency.allCases) { currency in
                    Text(currency.rawValue).tag(currency)
                }
            }

            Toggle("Include in totals", isOn: $account.includeInTotals)
        }
        .padding(.vertical, 4)
        .onChange(of: account.currency) { oldCurrency, newCurrency in
            guard oldCurrency != newCurrency else { return }
            account.openingBalance = account.openingBalance.recast(to: newCurrency)
            onCurrencyChange(account.id, oldCurrency, newCurrency)
        }
    }
}

private struct ImportReviewTransactionRow: View {
    @Binding var transaction: LedgerTransaction
    let rowNumber: Int
    let accounts: [Account]
    let categories: [LedgerCategory]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: transaction.kind == .income ? "arrow.down.left" : transaction.kind == .transfer ? "arrow.left.arrow.right" : "arrow.up.right")
                    .foregroundStyle(transaction.kind == .income ? PocketLedgerTheme.income : PocketLedgerTheme.accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.note)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text("Imported row \(rowNumber) · \(transaction.date.formatted(.dateTime.month(.abbreviated).day().year())) · \(transaction.kind.displayName)")
                        .font(.caption)
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                }
                Spacer(minLength: 8)
                Text((transaction.outflows.first?.money ?? transaction.inflows.first?.money)?.formatted ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.trailing)
            }

            Picker("Account", selection: sourceAccountBinding) {
                ForEach(sourceAccountOptions) { account in
                    Text(accountLabel(account)).tag(Optional(account.id))
                }
            }

            if transaction.kind == .transfer {
                Picker("Destination", selection: destinationAccountBinding) {
                    ForEach(destinationAccountOptions) { account in
                        Text(accountLabel(account)).tag(Optional(account.id))
                    }
                }
            }

            Picker("Category", selection: $transaction.categoryID) {
                Text("Uncategorized").tag(UUID?.none)
                ForEach(categories) { category in
                    Text(categoryPath(for: category.id)).tag(Optional(category.id))
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var sourceAccountOptions: [Account] {
        guard let money = transaction.kind == .income
            ? transaction.inflows.first?.money
            : transaction.outflows.first?.money else {
            return accounts
        }
        return accounts.filter { $0.currency == money.currency }
    }

    private var destinationAccountOptions: [Account] {
        guard let money = transaction.inflows.first?.money else { return accounts }
        return accounts.filter { $0.currency == money.currency }
    }

    private var sourceAccountBinding: Binding<UUID?> {
        Binding(
            get: {
                transaction.kind == .income
                    ? transaction.inflows.first?.accountID
                    : transaction.outflows.first?.accountID
            },
            set: { id in updateAccount(id, destination: false) }
        )
    }

    private var destinationAccountBinding: Binding<UUID?> {
        Binding(
            get: { transaction.inflows.first?.accountID },
            set: { id in updateAccount(id, destination: true) }
        )
    }

    private func updateAccount(_ id: UUID?, destination: Bool) {
        guard let id else { return }
        if destination {
            guard !transaction.inflows.isEmpty else { return }
            transaction.inflows[0].accountID = id
        } else if transaction.kind == .income {
            guard !transaction.inflows.isEmpty else { return }
            transaction.inflows[0].accountID = id
        } else {
            guard !transaction.outflows.isEmpty else { return }
            transaction.outflows[0].accountID = id
        }
    }

    private func accountLabel(_ account: Account) -> String {
        "\(account.name) · \(account.currency.rawValue)\(account.isArchived ? " · Archived" : "")"
    }

    private func categoryPath(for categoryID: UUID?) -> String {
        guard let categoryID else { return "Uncategorized" }

        var names: [String] = []
        var currentID: UUID? = categoryID
        var visited: Set<UUID> = []
        while let id = currentID,
              visited.insert(id).inserted,
              let category = categories.first(where: { $0.id == id }) {
            names.append(category.name)
            currentID = category.parentID
        }
        return names.reversed().joined(separator: " / ")
    }
}
