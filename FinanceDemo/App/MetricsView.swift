import Charts
import Foundation
import SwiftUI

private enum MetricsPeriod: String, CaseIterable, Identifiable {
    case month = "Month"
    case year = "Year"
    case custom = "Custom"

    var id: String { rawValue }
}

private typealias CategoryMetric = MetricsCategorySnapshot

private struct CategoryMonthPoint: Identifiable {
    let date: Date
    let amount: Int64

    var id: Date { date }
}

private struct MetricsReportShareItem: Identifiable {
    let url: URL

    var id: URL { url }
}

private struct CategoryMetricsDetailSnapshot {
    let monthlyPoints: [CategoryMonthPoint]
    let selectedMonthTransactions: [LedgerTransaction]
    let selectedMonthTotal: Int64

    static var empty: CategoryMetricsDetailSnapshot {
        CategoryMetricsDetailSnapshot(
            monthlyPoints: [],
            selectedMonthTransactions: [],
            selectedMonthTotal: 0
        )
    }

    static func make(
        index: LedgerIndex,
        categoryID: UUID?,
        currency: LedgerCurrency,
        anchorDate: Date,
        calendar: Calendar = .current
    ) -> CategoryMetricsDetailSnapshot {
        let currentMonth = calendar.dateInterval(of: .month, for: anchorDate)?.start ?? anchorDate
        let monthStarts = (0..<7).compactMap {
            calendar.date(byAdding: .month, value: $0 - 6, to: currentMonth)
                .flatMap { calendar.dateInterval(of: .month, for: $0)?.start }
        }
        guard let firstMonth = monthStarts.first,
              let lastMonth = monthStarts.last,
              let lastInterval = calendar.dateInterval(of: .month, for: lastMonth) else {
            return .empty
        }

        let range = DateInterval(start: firstMonth, end: lastInterval.end)
        var monthlyAmounts = monthStarts.reduce(into: [Date: Int64]()) { result, month in
            result[month] = 0
        }
        var selectedMonthTransactions: [LedgerTransaction] = []
        var selectedMonthTotal: Int64 = 0

        for transaction in index.sortedTransactions {
            guard transaction.kind == .expense,
                  range.contains(transaction.date),
                  transaction.categoryID == categoryID,
                  transaction.outflows.contains(where: {
                      $0.money.currency == currency
                          && index.includesInTotals(accountID: $0.accountID)
                  }),
                  let monthStart = calendar.dateInterval(of: .month, for: transaction.date)?.start else {
                continue
            }

            let outflowAmount = transaction.outflows.reduce(Int64.zero) { total, movement in
                guard movement.money.currency == currency,
                      index.includesInTotals(accountID: movement.accountID) else {
                    return total
                }
                return total + movement.money.minorUnits
            }
            monthlyAmounts[monthStart, default: 0] += outflowAmount

            if monthStart == currentMonth {
                selectedMonthTransactions.append(transaction)
                selectedMonthTotal += outflowAmount
            }
        }

        return CategoryMetricsDetailSnapshot(
            monthlyPoints: monthStarts.map {
                CategoryMonthPoint(date: $0, amount: monthlyAmounts[$0] ?? 0)
            },
            selectedMonthTransactions: selectedMonthTransactions,
            selectedMonthTotal: selectedMonthTotal
        )
    }
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
    @State private var snapshot = MetricsSnapshot.empty

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

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                PocketGlassContainer(spacing: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        screenHeader
                        periodControls
                        periodNavigator
                        totalsHeader(snapshot)
                        spendingChart(snapshot)
                        categoryRows(snapshot)
                        activityMix(snapshot)
                    }
                    .padding(.horizontal, PocketLedgerTheme.screenHorizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .pocketScreen()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: refreshSnapshot)
            .onChange(of: period) { _, _ in refreshSnapshot() }
            .onChange(of: selectedCurrency) { _, _ in refreshSnapshot() }
            .onChange(of: anchorDate) { _, _ in refreshSnapshot() }
            .onChange(of: customStart) { _, _ in refreshSnapshot() }
            .onChange(of: customEnd) { _, _ in refreshSnapshot() }
            .onChange(of: selectedCategoryID) { _, _ in refreshSnapshot() }
            .onChange(of: store.ledgerRevision) { _, _ in refreshSnapshot() }
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
                    .font(.largeTitle.weight(.semibold))
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
                .accessibilityIdentifier("metrics-period-picker")

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
                        .accessibilityIdentifier("metrics-period-title")

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

    private func totalsHeader(_ snapshot: MetricsSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Income")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                Text(Money(currency: selectedCurrency, minorUnits: snapshot.income).formatted)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(PocketLedgerTheme.income)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("Expenses")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                Text(Money(currency: selectedCurrency, minorUnits: snapshot.expenses).formatted)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(PocketLedgerTheme.warning)
            }
        }
        .padding(.bottom, 12)
    }

    private func spendingChart(_ snapshot: MetricsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Spending by category")
                    .font(.title3.weight(.bold))
                Spacer()
                Text("\(snapshot.filteredTransactions.count) entries")
                    .font(.caption)
                    .foregroundStyle(PocketLedgerTheme.textTertiary)
            }

            if snapshot.categories.isEmpty {
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
                    Chart(snapshot.categories) { metric in
                        SectorMark(
                            angle: .value("Amount", Double(metric.amount)),
                            innerRadius: .ratio(0.61),
                            angularInset: 1.5
                        )
                        .foregroundStyle(chartColor(for: metric.colorIndex))
                        .annotation(position: .overlay) {
                            if share(for: metric, total: snapshot.expenses) >= 0.08 {
                                Text("\(percentage(for: metric, total: snapshot.expenses))%")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(height: 246)

                    VStack(spacing: 3) {
                        Text(Money(currency: selectedCurrency, minorUnits: snapshot.expenses).formatted)
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

    private func categoryRows(_ snapshot: MetricsSnapshot) -> some View {
        VStack(spacing: 0) {
            if snapshot.categories.isEmpty {
                EmptyView()
            } else {
                ForEach(snapshot.categories) { metric in
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
                            Text("\(percentage(for: metric, total: snapshot.expenses))%")
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

                    if metric.id != snapshot.categories.last?.id {
                        Divider().overlay(PocketLedgerTheme.divider)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .pocketGroupedSurface(cornerRadius: 18)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(PocketLedgerTheme.divider, lineWidth: 1)
        }
        .padding(.top, 12)
    }

    private func activityMix(_ snapshot: MetricsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity mix")
                .font(.title3.weight(.bold))

            HStack(spacing: 10) {
                mixMetric(title: "Expenses", count: snapshot.activityCounts[.expense] ?? 0, tint: PocketLedgerTheme.warning)
                mixMetric(title: "Income", count: snapshot.activityCounts[.income] ?? 0, tint: PocketLedgerTheme.income)
                mixMetric(title: "Transfers", count: snapshot.activityCounts[.transfer] ?? 0, tint: PocketLedgerTheme.positive)
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

    private func share(for metric: CategoryMetric, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return Double(metric.amount) / Double(total)
    }

    private func percentage(for metric: CategoryMetric, total: Int64) -> Int {
        Int((share(for: metric, total: total) * 100).rounded())
    }

    private func categoryIcon(for categoryID: UUID?) -> String {
        store.ledgerIndex.categorySystemImage(for: categoryID)
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

    private func refreshSnapshot() {
        snapshot = MetricsSnapshot.make(
            index: store.ledgerIndex,
            interval: interval,
            selectedCurrency: selectedCurrency,
            selectedCategoryID: selectedCategoryID
        )
    }

    private func generateReport() {
        let currentSnapshot = MetricsSnapshot.make(
            index: store.ledgerIndex,
            interval: interval,
            selectedCurrency: selectedCurrency,
            selectedCategoryID: selectedCategoryID
        )
        let report = MetricsReportData(
            periodTitle: periodTitle,
            dateRange: intervalLabel,
            currency: selectedCurrency,
            categoryScope: selectedCategoryID.map { store.categoryPath(for: $0) } ?? "All categories",
            income: Money(currency: selectedCurrency, minorUnits: currentSnapshot.income),
            expenses: Money(currency: selectedCurrency, minorUnits: currentSnapshot.expenses),
            entryCount: currentSnapshot.filteredTransactions.count,
            activityCounts: currentSnapshot.activityCounts,
            categories: currentSnapshot.categories.map {
                MetricsReportCategory(
                    title: $0.title,
                    amount: Money(currency: $0.currency, minorUnits: $0.amount),
                    count: $0.count,
                    percentage: percentage(for: $0, total: currentSnapshot.expenses)
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
    @State private var snapshot = CategoryMetricsDetailSnapshot.empty

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

    var body: some View {
        ScrollView(showsIndicators: false) {
            PocketGlassContainer(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    detailHeader
                    lineChart(snapshot)
                    detailCategoryRow(snapshot)
                    transactionRows(snapshot)
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
        .onAppear(perform: refreshSnapshot)
        .onChange(of: anchorDate) { _, _ in refreshSnapshot() }
        .onChange(of: store.ledgerRevision) { _, _ in refreshSnapshot() }
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

    private func lineChart(_ snapshot: CategoryMetricsDetailSnapshot) -> some View {
        let maximum = max(snapshot.monthlyPoints.map(\.amount).max() ?? 1, 1)
        let currentMonth = Calendar.current.dateInterval(of: .month, for: anchorDate)?.start ?? anchorDate

        return Chart(snapshot.monthlyPoints) { point in
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
            .symbolSize(point.date == currentMonth ? 80 : 42)
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

    private func detailCategoryRow(_ snapshot: CategoryMetricsDetailSnapshot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: categoryIcon)
                .foregroundStyle(PocketLedgerTheme.accent)
                .frame(width: 24)

            Text(categoryTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer()

            Text(Money(currency: currency, minorUnits: snapshot.selectedMonthTotal).formatted)
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

    private func transactionRows(_ snapshot: CategoryMetricsDetailSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Transactions")
                .font(.title3.weight(.bold))
                .padding(.top, 20)
                .padding(.bottom, 8)

            if snapshot.selectedMonthTransactions.isEmpty {
                Text("No transactions in this month.")
                    .font(.subheadline)
                    .foregroundStyle(PocketLedgerTheme.textSecondary)
                    .padding(.vertical, 24)
            } else {
                ForEach(snapshot.selectedMonthTransactions) { transaction in
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

                    if transaction.id != snapshot.selectedMonthTransactions.last?.id {
                        Divider().overlay(PocketLedgerTheme.divider)
                    }
                }
            }
        }
    }

    private var categoryIcon: String {
        store.ledgerIndex.categorySystemImage(for: categoryID)
    }

    private func transactionAmount(_ transaction: LedgerTransaction) -> Int64 {
        store.ledgerIndex.netExpenseAmount(transaction, currency: currency)
    }

    private func accountNames(for transaction: LedgerTransaction) -> String {
        let names = transaction.outflows.compactMap { movement -> String? in
            guard store.ledgerIndex.includesInTotals(accountID: movement.accountID) else { return nil }
            return store.ledgerIndex.account(with: movement.accountID)?.name
        }
        return names.isEmpty ? "Expense" : names.joined(separator: ", ")
    }

    private func refreshSnapshot() {
        snapshot = CategoryMetricsDetailSnapshot.make(
            index: store.ledgerIndex,
            categoryID: categoryID,
            currency: currency,
            anchorDate: anchorDate
        )
    }

    private func moveMonth(by value: Int) {
        anchorDate = Calendar.current.date(byAdding: .month, value: value, to: anchorDate) ?? anchorDate
    }
}
