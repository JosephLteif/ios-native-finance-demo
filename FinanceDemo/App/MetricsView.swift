import Charts
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
    let categoryID: UUID?
    let title: String
    let currency: LedgerCurrency
    let amount: Int64
    let count: Int
    let colorIndex: Int
}

private struct CategoryMonthPoint: Identifiable {
    let date: Date
    let amount: Int64

    var id: Date { date }
}

private struct MetricsReportShareItem: Identifiable {
    let url: URL

    var id: URL { url }
}

@MainActor
struct MetricsView: View {
    @ObservedObject var store: LedgerStore

    @State private var period: MetricsPeriod = .month
    @State private var selectedCurrency: LedgerCurrency = .usd
    @State private var anchorDate = Date.now
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: Date.now) ?? Date.now
    @State private var customEnd = Date.now
    @State private var selectedCategoryID: UUID?
    @State private var reportToShare: MetricsReportShareItem?
    @State private var reportError: String?

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
            interval.contains(transaction.date)
                && matchesCategory(transaction)
                && financeCategoryIncludedInTotals(transaction.categoryID, in: store.data.categories)
                && transactionHasIncludedAccount(transaction)
        }
    }

    private var expenseTotals: [LedgerCurrency: Int64] {
        var totals: [LedgerCurrency: Int64] = [:]
        for transaction in filteredTransactions where transaction.kind == .expense {
            for currency in LedgerCurrency.allCases {
                totals[currency, default: 0] += financeNetExpenseAmount(
                    transaction,
                    currency: currency,
                    in: store.data
                )
            }
        }
        return totals
    }

    private var incomeTotals: [LedgerCurrency: Int64] {
        totals(for: .income, movements: \LedgerTransaction.inflows)
    }

    private var selectedCurrencyExpense: Int64 {
        expenseTotals[selectedCurrency] ?? 0
    }

    private var categoryMetrics: [CategoryMetric] {
        var metrics: [String: (categoryID: UUID?, title: String, amount: Int64, count: Int)] = [:]

        for transaction in filteredTransactions where transaction.kind == .expense {
            let categoryID = transaction.categoryID
            let categoryName = store.categoryPath(for: categoryID)
            let amount = financeNetExpenseAmount(
                transaction,
                currency: selectedCurrency,
                in: store.data
            )
            guard amount > 0 else { continue }

            let key = "\(categoryID?.uuidString ?? "uncategorized")-\(selectedCurrency.rawValue)"
            let current = metrics[key] ?? (categoryID, categoryName, 0, 0)
            metrics[key] = (
                current.categoryID,
                current.title,
                current.amount + amount,
                current.count + 1
            )
        }

        return metrics.values
            .sorted { $0.amount > $1.amount }
            .enumerated()
            .map { index, metric in
                CategoryMetric(
                    id: "\(metric.categoryID?.uuidString ?? "uncategorized")-\(selectedCurrency.rawValue)",
                    categoryID: metric.categoryID,
                    title: metric.title,
                    currency: selectedCurrency,
                    amount: metric.amount,
                    count: metric.count,
                    colorIndex: index
                )
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                PocketGlassContainer(spacing: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        screenHeader
                        periodControls
                        periodNavigator
                        totalsHeader
                        spendingChart
                        categoryRows
                        activityMix
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .pocketScreen()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $reportToShare) { report in
                MetricsReportShareSheet(url: report.url)
            }
            .alert("Report not created", isPresented: reportErrorPresented) {
                Button("OK") { reportError = nil }
            } message: {
                Text(reportError ?? "")
            }
        }
    }

    private var screenHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Metrics")
                    .font(.largeTitle.weight(.bold))
                Text("See how your money moves")
                    .font(.subheadline)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
            }

            Spacer(minLength: 8)

            Button(action: generateReport) {
                Image(systemName: "square.and.arrow.up")
                    .font(.headline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .pocketGlassSurface(cornerRadius: 22, tint: PocketLedgerTheme.accent.opacity(0.14), interactive: true)
                    .overlay {
                        Circle().stroke(PocketLedgerTheme.divider, lineWidth: 1)
                    }
            }
            .foregroundStyle(PocketLedgerTheme.accent)
            .accessibilityLabel("Share metrics PDF report")
            .accessibilityHint("Creates a shareable PDF report")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 14)
    }

    private var periodControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Picker("Period", selection: $period) {
                    ForEach(MetricsPeriod.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Currency", selection: $selectedCurrency) {
                    ForEach(LedgerCurrency.allCases) { currency in
                        Text(currency.rawValue).tag(currency)
                    }
                }
                .pickerStyle(.menu)
                .tint(PocketLedgerTheme.textPrimary)
                .padding(.horizontal, 8)
                .pocketGlassSurface(cornerRadius: 10, tint: PocketLedgerTheme.surfaceElevated.opacity(0.22))
            }

            Picker("Category", selection: $selectedCategoryID) {
                Text("All categories").tag(UUID?.none)
                ForEach(store.activeCategories) { category in
                    Text(store.categoryPath(for: category.id))
                        .tag(Optional(category.id))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tint(PocketLedgerTheme.textPrimary)
        }
        .padding(4)
        .pocketGlassSurface(cornerRadius: 13)
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(PocketLedgerTheme.divider, lineWidth: 1)
        }
    }

    private var periodNavigator: some View {
        VStack(spacing: 10) {
            if period == .custom {
                DatePicker("From", selection: $customStart, displayedComponents: .date)
                DatePicker("To", selection: $customEnd, displayedComponents: .date)
            } else {
                HStack {
                    Button {
                        movePeriod(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Previous period")

                    Spacer()

                    Text(periodTitle)
                        .font(.headline.weight(.semibold))

                    Spacer()

                    Button {
                        movePeriod(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.headline.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Next period")
                }
            }

            Text(intervalLabel)
                .font(.caption)
                .foregroundStyle(PocketLedgerTheme.textTertiary)
        }
        .foregroundStyle(PocketLedgerTheme.textPrimary)
        .padding(.vertical, 12)
    }

    private var totalsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Income")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                Text(Money(currency: selectedCurrency, minorUnits: incomeTotals[selectedCurrency] ?? 0).formatted)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(PocketLedgerTheme.income)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("Expenses")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                Text(Money(currency: selectedCurrency, minorUnits: selectedCurrencyExpense).formatted)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(PocketLedgerTheme.warning)
            }
        }
        .padding(.bottom, 12)
    }

    private var spendingChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Spending by category")
                    .font(.title3.weight(.bold))
                Spacer()
                Text("\(filteredTransactions.count) entries")
                    .font(.caption)
                    .foregroundStyle(PocketLedgerTheme.textTertiary)
            }

            if categoryMetrics.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.pie")
                        .font(.title2)
                        .foregroundStyle(PocketLedgerTheme.textTertiary)
                    Text("No expense activity in this range.")
                        .font(.subheadline)
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 46)
            } else {
                ZStack {
                    Chart(categoryMetrics) { metric in
                        SectorMark(
                            angle: .value("Amount", Double(metric.amount)),
                            innerRadius: .ratio(0.61),
                            angularInset: 1.5
                        )
                        .foregroundStyle(chartColor(for: metric.colorIndex))
                        .annotation(position: .overlay) {
                            if share(for: metric) >= 0.08 {
                                Text("\(percentage(for: metric))%")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(height: 246)

                    VStack(spacing: 3) {
                        Text(Money(currency: selectedCurrency, minorUnits: selectedCurrencyExpense).formatted)
                            .font(.headline.weight(.bold).monospacedDigit())
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                        Text("TOTAL SPENT")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(PocketLedgerTheme.textTertiary)
                    }
                }
            }
        }
        .pocketCard()
    }

    private var categoryRows: some View {
        VStack(spacing: 0) {
            if categoryMetrics.isEmpty {
                EmptyView()
            } else {
                ForEach(categoryMetrics) { metric in
                    NavigationLink {
                        CategoryMetricsDetailView(
                            store: store,
                            categoryID: metric.categoryID,
                            categoryTitle: metric.title,
                            currency: metric.currency,
                            anchorDate: anchorDate
                        )
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(percentage(for: metric))%")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 30)
                                .background(chartColor(for: metric.colorIndex), in: RoundedRectangle(cornerRadius: 7))

                            Image(systemName: categoryIcon(for: metric.categoryID))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(chartColor(for: metric.colorIndex))
                                .frame(width: 22)

                            Text(metric.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Text(Money(currency: metric.currency, minorUnits: metric.amount).formatted)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)

                    if metric.id != categoryMetrics.last?.id {
                        Divider().overlay(PocketLedgerTheme.divider)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .pocketGlassSurface(cornerRadius: 18)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(PocketLedgerTheme.divider, lineWidth: 1)
        }
        .padding(.top, 12)
    }

    private var activityMix: some View {
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
        .padding(.top, 18)
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

    private func chartColor(for index: Int) -> Color {
        let colors = [
            PocketLedgerTheme.warning,
            PocketLedgerTheme.accent,
            PocketLedgerTheme.income,
            PocketLedgerTheme.positive,
            PocketLedgerTheme.accent.opacity(0.62),
            PocketLedgerTheme.warning.opacity(0.62),
            PocketLedgerTheme.income.opacity(0.62)
        ]
        return colors[index % colors.count]
    }

    private func share(for metric: CategoryMetric) -> Double {
        guard selectedCurrencyExpense > 0 else { return 0 }
        return Double(metric.amount) / Double(selectedCurrencyExpense)
    }

    private func percentage(for metric: CategoryMetric) -> Int {
        Int((share(for: metric) * 100).rounded())
    }

    private func categoryIcon(for categoryID: UUID?) -> String {
        guard let categoryID,
              let category = store.data.categories.first(where: { $0.id == categoryID }) else {
            return "tag.fill"
        }
        return category.systemImage
    }

    private func totals(
        for kind: TransactionKind,
        movements: KeyPath<LedgerTransaction, [MoneyMovement]>
    ) -> [LedgerCurrency: Int64] {
        var totals: [LedgerCurrency: Int64] = [:]
        for transaction in filteredTransactions where transaction.kind == kind {
            for movement in transaction[keyPath: movements] {
                guard store.includesInTotals(accountID: movement.accountID) else { continue }
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

    private func transactionHasIncludedAccount(_ transaction: LedgerTransaction) -> Bool {
        switch transaction.kind {
        case .expense:
            return transaction.outflows.contains {
                store.includesInTotals(accountID: $0.accountID)
            }
        case .income:
            return transaction.inflows.contains {
                store.includesInTotals(accountID: $0.accountID)
            }
        case .transfer:
            return (transaction.outflows + transaction.inflows).contains {
                store.includesInTotals(accountID: $0.accountID)
            }
        }
    }

    private func movePeriod(by value: Int) {
        let component: Calendar.Component = period == .year ? .year : .month
        anchorDate = Calendar.current.date(byAdding: component, value: value, to: anchorDate) ?? anchorDate
    }

    private var periodTitle: String {
        switch period {
        case .month:
            return anchorDate.formatted(.dateTime.month(.abbreviated).year())
        case .year:
            return anchorDate.formatted(.dateTime.year())
        case .custom:
            return intervalLabel
        }
    }

    private var intervalLabel: String {
        let start = interval.start.formatted(.dateTime.month(.abbreviated).day().year())
        let endDate = interval.end.addingTimeInterval(-1)
        let end = endDate.formatted(.dateTime.month(.abbreviated).day().year())
        return start == end ? start : "\(start) – \(end)"
    }

    private var reportErrorPresented: Binding<Bool> {
        Binding(
            get: { reportError != nil },
            set: { if !$0 { reportError = nil } }
        )
    }

    private func generateReport() {
        let report = MetricsReportData(
            periodTitle: periodTitle,
            dateRange: intervalLabel,
            currency: selectedCurrency,
            categoryScope: selectedCategoryID.map { store.categoryPath(for: $0) } ?? "All categories",
            income: Money(currency: selectedCurrency, minorUnits: incomeTotals[selectedCurrency] ?? 0),
            expenses: Money(currency: selectedCurrency, minorUnits: selectedCurrencyExpense),
            entryCount: filteredTransactions.count,
            activityCounts: Dictionary(grouping: filteredTransactions, by: \.kind).mapValues { $0.count },
            categories: categoryMetrics.map {
                MetricsReportCategory(
                    title: $0.title,
                    amount: Money(currency: $0.currency, minorUnits: $0.amount),
                    count: $0.count,
                    percentage: percentage(for: $0)
                )
            },
            generatedAt: .now
        )

        do {
            let url = try MetricsReportPDF.writeShareableFile(for: report)
            reportToShare = MetricsReportShareItem(url: url)
        } catch {
            reportError = error.localizedDescription
        }
    }
}

@MainActor
private struct CategoryMetricsDetailView: View {
    @ObservedObject var store: LedgerStore

    let categoryID: UUID?
    let categoryTitle: String
    let currency: LedgerCurrency

    @State private var anchorDate: Date

    init(
        store: LedgerStore,
        categoryID: UUID?,
        categoryTitle: String,
        currency: LedgerCurrency,
        anchorDate: Date
    ) {
        self.store = store
        self.categoryID = categoryID
        self.categoryTitle = categoryTitle
        self.currency = currency
        _anchorDate = State(initialValue: anchorDate)
    }

    private var monthInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: anchorDate)
            ?? DateInterval(start: anchorDate, duration: 31 * 24 * 60 * 60)
    }

    private var monthlyPoints: [CategoryMonthPoint] {
        let calendar = Calendar.current
        let currentMonth = calendar.dateInterval(of: .month, for: anchorDate)?.start ?? anchorDate

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: offset - 6, to: currentMonth),
                  let interval = calendar.dateInterval(of: .month, for: date) else {
                return nil
            }

            let amount = expenseTransactions(in: interval).reduce(Int64.zero) { total, transaction in
                total + transaction.outflows
                    .filter {
                        $0.money.currency == currency
                            && store.includesInTotals(accountID: $0.accountID)
                    }
                    .reduce(Int64.zero) { $0 + $1.money.minorUnits }
            }
            return CategoryMonthPoint(date: date, amount: amount)
        }
    }

    private var selectedMonthTransactions: [LedgerTransaction] {
        expenseTransactions(in: monthInterval)
            .sorted { $0.date > $1.date }
    }

    private var selectedMonthTotal: Int64 {
        selectedMonthTransactions.reduce(Int64.zero) { total, transaction in
            total + transaction.outflows
                .filter {
                    $0.money.currency == currency
                        && store.includesInTotals(accountID: $0.accountID)
                }
                .reduce(Int64.zero) { $0 + $1.money.minorUnits }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            PocketGlassContainer(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    detailHeader
                    lineChart
                    detailCategoryRow
                    transactionRows
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .pocketScreen()
        .navigationTitle(categoryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var detailHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    moveMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous month")

                Spacer()

                Text(anchorDate.formatted(.dateTime.month(.abbreviated).year()))
                    .font(.headline.weight(.semibold))

                Spacer()

                Button {
                    moveMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next month")
            }

            HStack {
                Text("Last 7 months")
                    .font(.caption)
                    .foregroundStyle(PocketLedgerTheme.textTertiary)
                Spacer()
                Text(currency.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PocketLedgerTheme.accent)
            }
        }
        .foregroundStyle(PocketLedgerTheme.textPrimary)
    }

    private var lineChart: some View {
        let maximum = max(monthlyPoints.map(\.amount).max() ?? 1, 1)

        return Chart(monthlyPoints) { point in
            LineMark(
                x: .value("Month", point.date, unit: .month),
                y: .value("Amount", Double(point.amount))
            )
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .foregroundStyle(PocketLedgerTheme.accent)

            PointMark(
                x: .value("Month", point.date, unit: .month),
                y: .value("Amount", Double(point.amount))
            )
            .foregroundStyle(PocketLedgerTheme.accent)
            .symbolSize(point.date == monthInterval.start ? 80 : 42)
            .annotation(position: .top, spacing: 6) {
                if point.amount > 0 {
                    Text(Money(currency: currency, minorUnits: point.amount).formatted)
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(PocketLedgerTheme.textSecondary)
                }
            }
        }
        .chartYScale(domain: 0...Double(maximum))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                    .foregroundStyle(PocketLedgerTheme.divider)
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
            }
        }
        .frame(height: 238)
        .padding(.top, 8)
    }

    private var detailCategoryRow: some View {
        HStack(spacing: 10) {
            Image(systemName: categoryIcon)
                .foregroundStyle(PocketLedgerTheme.accent)
                .frame(width: 24)

            Text(categoryTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer()

            Text(Money(currency: currency, minorUnits: selectedMonthTotal).formatted)
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 14)
        .pocketGlassSurface(cornerRadius: 16)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(PocketLedgerTheme.divider, lineWidth: 1)
        }
        .padding(.top, 10)
    }

    private var transactionRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Transactions")
                .font(.title3.weight(.bold))
                .padding(.top, 20)
                .padding(.bottom, 8)

            if selectedMonthTransactions.isEmpty {
                Text("No transactions in this month.")
                    .font(.subheadline)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                    .padding(.vertical, 24)
            } else {
                ForEach(selectedMonthTransactions) { transaction in
                    HStack(spacing: 12) {
                        VStack(spacing: 0) {
                            Text(transaction.date.formatted(.dateTime.day()))
                                .font(.headline.weight(.bold).monospacedDigit())
                            Text(transaction.date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(PocketLedgerTheme.textSecondary)
                        }
                        .frame(width: 42)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(accountNames(for: transaction))
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(transaction.note)
                                .font(.caption)
                                .foregroundStyle(PocketLedgerTheme.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Text(Money(currency: currency, minorUnits: transactionAmount(transaction)).formatted)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(PocketLedgerTheme.warning)
                    }
                    .padding(.vertical, 12)

                    if transaction.id != selectedMonthTransactions.last?.id {
                        Divider().overlay(PocketLedgerTheme.divider)
                    }
                }
            }
        }
    }

    private var categoryIcon: String {
        guard let categoryID,
              let category = store.data.categories.first(where: { $0.id == categoryID }) else {
            return "tag.fill"
        }
        return category.systemImage
    }

    private func expenseTransactions(in interval: DateInterval) -> [LedgerTransaction] {
        store.data.transactions.filter { transaction in
            interval.contains(transaction.date)
                && transaction.kind == .expense
                && matchesCategory(transaction)
                && transaction.outflows.contains {
                    $0.money.currency == currency
                        && store.includesInTotals(accountID: $0.accountID)
                }
        }
    }

    private func matchesCategory(_ transaction: LedgerTransaction) -> Bool {
        transaction.categoryID == categoryID
    }

    private func transactionAmount(_ transaction: LedgerTransaction) -> Int64 {
        financeNetExpenseAmount(transaction, currency: currency, in: store.data)
    }

    private func accountNames(for transaction: LedgerTransaction) -> String {
        let names = transaction.outflows.compactMap { movement -> String? in
            guard store.includesInTotals(accountID: movement.accountID) else { return nil }
            return store.data.accounts.first(where: { $0.id == movement.accountID })?.name
        }
        return names.isEmpty ? "Expense" : names.joined(separator: ", ")
    }

    private func moveMonth(by value: Int) {
        anchorDate = Calendar.current.date(byAdding: .month, value: value, to: anchorDate) ?? anchorDate
    }
}
