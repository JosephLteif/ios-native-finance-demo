import Foundation
import SwiftUI

private enum MetricsPeriod: String, CaseIterable, Identifiable {
    case month = "Month"
    case year = "Year"
    case custom = "Custom"

    var id: String { rawValue }
}

private struct CategoryMetric: Identifiable {
    let id: String
    let title: String
    let currency: LedgerCurrency
    var amount: Int64
    var count: Int
}

@MainActor
struct MetricsView: View {
    @ObservedObject var store: LedgerStore

    @State private var period: MetricsPeriod = .month
    @State private var anchorDate = Date.now
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: Date.now) ?? Date.now
    @State private var customEnd = Date.now
    @State private var selectedCategoryID: UUID?

    private var interval: DateInterval {
        let calendar = Calendar.current

        switch period {
        case .month:
            return calendar.dateInterval(of: .month, for: anchorDate)
                ?? DateInterval(start: anchorDate, duration: 31 * 24 * 60 * 60)
        case .year:
            return calendar.dateInterval(of: .year, for: anchorDate)
                ?? DateInterval(start: anchorDate, duration: 365 * 24 * 60 * 60)
        case .custom:
            let start = calendar.startOfDay(for: customStart)
            let endOfSelectedDay = calendar.startOfDay(for: customEnd)
            let end = endOfSelectedDay > start
                ? calendar.date(byAdding: .day, value: 1, to: endOfSelectedDay) ?? endOfSelectedDay
                : calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        }
    }

    private var filteredTransactions: [LedgerTransaction] {
        store.recentTransactions.filter { transaction in
            interval.contains(transaction.date) && matchesCategory(transaction)
        }
    }

    private var expenseTotals: [LedgerCurrency: Int64] {
        totals(for: .expense, movements: \LedgerTransaction.outflows)
    }

    private var incomeTotals: [LedgerCurrency: Int64] {
        totals(for: .income, movements: \LedgerTransaction.inflows)
    }

    private var categoryMetrics: [CategoryMetric] {
        var metrics: [String: CategoryMetric] = [:]

        for transaction in filteredTransactions where transaction.kind == .expense {
            let categoryName = store.categoryPath(for: transaction.categoryID)
            let movementsByCurrency = Dictionary(grouping: transaction.outflows) { $0.money.currency }
            for (currency, movements) in movementsByCurrency {
                let key = "\(categoryName)-\(currency.rawValue)"
                var metric = metrics[key] ?? CategoryMetric(
                    id: key,
                    title: categoryName,
                    currency: currency,
                    amount: 0,
                    count: 0
                )
                metric.amount += movements.reduce(Int64.zero) { $0 + $1.money.minorUnits }
                metric.count += 1
                metrics[key] = metric
            }
        }

        return metrics.values.sorted {
            if $0.currency == $1.currency {
                return $0.amount > $1.amount
            }
            return $0.currency.rawValue < $1.currency.rawValue
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    screenHeader
                    filterCard
                    overviewCard
                    categoryBreakdown
                    transactionMix
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .pocketScreen()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var screenHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Metrics")
                .font(.system(size: 29, weight: .bold, design: .rounded))
            Text("Understand where your money moves")
                .font(.subheadline)
                .foregroundStyle(PocketLedgerTheme.textSecondary)
        }
    }

    private var filterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Period", selection: $period) {
                ForEach(MetricsPeriod.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)

            switch period {
            case .month:
                DatePicker("Month", selection: $anchorDate, displayedComponents: .date)
            case .year:
                DatePicker("Year", selection: $anchorDate, displayedComponents: .date)
            case .custom:
                DatePicker("From", selection: $customStart, displayedComponents: .date)
                DatePicker("To", selection: $customEnd, displayedComponents: .date)
            }

            Picker("Category", selection: $selectedCategoryID) {
                Text("All categories").tag(UUID?.none)
                ForEach(store.data.categories) { category in
                    Text(store.categoryPath(for: category.id))
                        .tag(Optional(category.id))
                }
            }

            Text(intervalLabel)
                .font(.caption)
                .foregroundStyle(PocketLedgerTheme.textTertiary)
        }
        .pocketCard()
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Overview")
                        .font(.title3.weight(.bold))
                    Text("\(filteredTransactions.count) transactions in this view")
                        .font(.caption)
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chart.xyaxis.line")
                    .font(.title3)
                    .foregroundStyle(PocketLedgerTheme.accent)
            }

            HStack(spacing: 10) {
                metricCard(
                    title: "USD spent",
                    value: Money(currency: .usd, minorUnits: expenseTotals[.usd] ?? 0).formatted,
                    tint: PocketLedgerTheme.warning
                )
                metricCard(
                    title: "USD in",
                    value: Money(currency: .usd, minorUnits: incomeTotals[.usd] ?? 0).formatted,
                    tint: PocketLedgerTheme.income
                )
            }

            HStack(spacing: 10) {
                metricCard(
                    title: "LBP spent",
                    value: Money(currency: .lbp, minorUnits: expenseTotals[.lbp] ?? 0).formatted,
                    tint: PocketLedgerTheme.warning
                )
                metricCard(
                    title: "LBP in",
                    value: Money(currency: .lbp, minorUnits: incomeTotals[.lbp] ?? 0).formatted,
                    tint: PocketLedgerTheme.income
                )
            }
        }
        .pocketCard()
    }

    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Spending by category")
                    .font(.title3.weight(.bold))
                Spacer()
                Text(period.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PocketLedgerTheme.textTertiary)
            }

            if categoryMetrics.isEmpty {
                Text("No expense activity in this range.")
                    .font(.subheadline)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                    .padding(.vertical, 8)
            } else {
                let maximum = max(categoryMetrics.map(\.amount).max() ?? 1, 1)
                VStack(spacing: 0) {
                    ForEach(categoryMetrics) { metric in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                Text(metric.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Spacer()
                                Text(Money(currency: metric.currency, minorUnits: metric.amount).formatted)
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(PocketLedgerTheme.warning)
                            }
                            HStack(spacing: 8) {
                                ProgressView(value: Double(metric.amount), total: Double(maximum))
                                    .tint(PocketLedgerTheme.warning)
                                Text("\(metric.count) \(metric.count == 1 ? "transaction" : "transactions")")
                                    .font(.caption2)
                                    .foregroundStyle(PocketLedgerTheme.textTertiary)
                                    .fixedSize()
                            }
                        }
                        .padding(.vertical, 10)

                        if metric.id != categoryMetrics.last?.id {
                            Divider().overlay(PocketLedgerTheme.divider)
                        }
                    }
                }
            }
        }
        .pocketCard()
    }

    private var transactionMix: some View {
        let counts = Dictionary(grouping: filteredTransactions, by: \LedgerTransaction.kind)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Activity mix")
                .font(.title3.weight(.bold))

            HStack(spacing: 10) {
                mixMetric(title: "Expenses", count: counts[.expense]?.count ?? 0, tint: PocketLedgerTheme.warning)
                mixMetric(title: "Income", count: counts[.income]?.count ?? 0, tint: PocketLedgerTheme.income)
                mixMetric(title: "Transfers", count: counts[.transfer]?.count ?? 0, tint: PocketLedgerTheme.positive)
            }
        }
        .pocketCard()
    }

    private func metricCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.45)
                .foregroundStyle(PocketLedgerTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(PocketLedgerTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14))
    }

    private func mixMetric(title: String, count: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text("\(count)")
                .font(.title3.weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(PocketLedgerTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func totals(
        for kind: TransactionKind,
        movements: KeyPath<LedgerTransaction, [MoneyMovement]>
    ) -> [LedgerCurrency: Int64] {
        var totals: [LedgerCurrency: Int64] = [:]
        for transaction in filteredTransactions where transaction.kind == kind {
            for movement in transaction[keyPath: movements] {
                totals[movement.money.currency, default: 0] += movement.money.minorUnits
            }
        }
        return totals
    }

    private func matchesCategory(_ transaction: LedgerTransaction) -> Bool {
        guard let selectedCategoryID else { return true }
        guard var currentID = transaction.categoryID else { return false }
        var visited: Set<UUID> = []

        while !visited.contains(currentID),
              let category = store.data.categories.first(where: { $0.id == currentID }) {
            if category.id == selectedCategoryID { return true }
            visited.insert(currentID)
            guard let parentID = category.parentID else { return false }
            currentID = parentID
        }

        return false
    }

    private var intervalLabel: String {
        let start = interval.start.formatted(.dateTime.month(.abbreviated).day().year())
        let endDate = interval.end.addingTimeInterval(-1)
        let end = endDate.formatted(.dateTime.month(.abbreviated).day().year())
        return start == end ? start : "\(start) – \(end)"
    }
}
