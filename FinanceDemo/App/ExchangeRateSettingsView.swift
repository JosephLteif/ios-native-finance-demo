import Foundation
import SwiftUI

private enum ExchangeRateSheet: Identifiable {
    case new
    case edit(ExchangeRate)

    var id: String {
        switch self {
        case .new:
            return "new"
        case .edit(let rate):
            return "edit-\(rate.id)"
        }
    }

    var rate: ExchangeRate? {
        switch self {
        case .new:
            return nil
        case .edit(let rate):
            return rate
        }
    }
}

@MainActor
struct ExchangeRatesView: View {
    @ObservedObject var store: LedgerStore
    @State private var sheet: ExchangeRateSheet?

    var body: some View {
        Form {
            Section {
                if store.data.exchangeRates.isEmpty {
                    ContentUnavailableView(
                        "No custom rates",
                        systemImage: "arrow.left.arrow.right",
                        description: Text("Add a rate to reuse it as the starting value for mixed-currency transactions.")
                    )
                } else {
                    ForEach(store.data.exchangeRates) { rate in
                        Button {
                            sheet = .edit(rate)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .foregroundStyle(PocketLedgerTheme.accent)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(rate.summary)
                                        .font(.subheadline.weight(.semibold))
                                    Text("Custom saved rate")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .foregroundStyle(PocketLedgerTheme.textPrimary)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.deleteExchangeRate(rate)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Saved rates")
            } footer: {
                Text("A rate means how many quote-currency units equal one base-currency unit. Saving a reverse pair replaces the existing pair.")
            }

            Section {
                Button {
                    sheet = .new
                } label: {
                    Label("Add exchange rate", systemImage: "plus.circle.fill")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .pocketScreen()
        .listRowBackground(.clear)
        .tint(PocketLedgerTheme.accent)
        .navigationTitle("Exchange rates")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { sheet in
            ExchangeRateEditor(store: store, existingRate: sheet.rate)
        }
    }
}

@MainActor
private struct ExchangeRateEditor: View {
    @ObservedObject var store: LedgerStore
    let existingRate: ExchangeRate?

    @Environment(\.dismiss) private var dismiss
    @State private var baseCurrency: LedgerCurrency
    @State private var quoteCurrency: LedgerCurrency
    @State private var rateText: String
    @State private var errorMessage: String?

    init(store: LedgerStore, existingRate: ExchangeRate?) {
        _store = ObservedObject(wrappedValue: store)
        self.existingRate = existingRate
        _baseCurrency = State(initialValue: existingRate?.baseCurrency ?? .usd)
        _quoteCurrency = State(initialValue: existingRate?.quoteCurrency ?? .lbp)
        _rateText = State(
            initialValue: existingRate.map {
                NSDecimalNumber(decimal: $0.quoteUnitsPerBaseUnit).stringValue
            } ?? "100000"
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rate") {
                    Picker("Base currency", selection: $baseCurrency) {
                        ForEach(LedgerCurrency.allCases) { currency in
                            Text("\(currency.rawValue) · \(currency.displayName)").tag(currency)
                        }
                    }

                    Picker("Quote currency", selection: $quoteCurrency) {
                        ForEach(LedgerCurrency.allCases) { currency in
                            Text("\(currency.rawValue) · \(currency.displayName)").tag(currency)
                        }
                    }

                    TextField("Quote units per base unit", text: $rateText)
                        .keyboardType(.decimalPad)

                    if let rate = parsedRate, baseCurrency != quoteCurrency {
                        Text("1 \(baseCurrency.rawValue) = \(NSDecimalNumber(decimal: rate).stringValue) \(quoteCurrency.rawValue)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("This saved rate is used as a starting value when a transaction includes these currencies. You can still override the rate on an individual transaction.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .pocketScreen()
            .listRowBackground(.clear)
            .tint(PocketLedgerTheme.accent)
            .navigationTitle(existingRate == nil ? "Add exchange rate" : "Edit exchange rate")
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
            .alert("Exchange rate not saved", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var parsedRate: Decimal? {
        Decimal(
            string: rateText.replacingOccurrences(of: ",", with: ""),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private var canSave: Bool {
        baseCurrency != quoteCurrency && (parsedRate ?? 0) > 0
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        guard let parsedRate, baseCurrency != quoteCurrency, parsedRate > 0 else {
            errorMessage = "Choose different currencies and enter a positive rate."
            return
        }

        let saved = store.upsertExchangeRate(
            ExchangeRate(
                baseCurrency: baseCurrency,
                quoteCurrency: quoteCurrency,
                quoteUnitsPerBaseUnit: parsedRate
            )
        )
        guard saved else {
            errorMessage = store.lastActionStatus ?? "The exchange rate could not be saved."
            return
        }
        dismiss()
    }
}
