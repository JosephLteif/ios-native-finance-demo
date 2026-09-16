import Foundation
import SwiftUI
import UIKit

struct MetricsReportCategory {
    let title: String
    let amount: Money
    let count: Int
    let percentage: Int
}

struct MetricsReportData {
    let periodTitle: String
    let dateRange: String
    let currency: LedgerCurrency
    let categoryScope: String
    let income: Money
    let expenses: Money
    let entryCount: Int
    let activityCounts: [TransactionKind: Int]
    let categories: [MetricsReportCategory]
    let generatedAt: Date
}

enum MetricsReportPDF {
    static func data(for report: MetricsReportData) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { context in
            let canvas = MetricsReportPDFCanvas(context: context, pageRect: pageRect)
            canvas.beginPage()
            canvas.drawReport(report)
            canvas.finishPage()
        }
    }
}

@MainActor
struct MetricsReportShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private final class MetricsReportPDFCanvas {
    private let context: UIGraphicsPDFRendererContext
    private let pageRect: CGRect
    private let contentRect: CGRect
    private var y: CGFloat = 0
    private var pageNumber = 0

    init(context: UIGraphicsPDFRendererContext, pageRect: CGRect) {
        self.context = context
        self.pageRect = pageRect
        contentRect = pageRect.insetBy(dx: 54, dy: 0)
    }

    func beginPage() {
        context.beginPage()
        pageNumber += 1
        y = 42

        drawFixed(
            "Pocket Ledger",
            in: CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: 16),
            font: .systemFont(ofSize: 10, weight: .semibold),
            color: .systemBlue
        )
        y += 28
        drawLine()
        y += 20
    }

    func finishPage() {
        drawFixed(
            "Metrics report - page \(pageNumber)",
            in: CGRect(x: contentRect.minX, y: pageRect.maxY - 38, width: contentRect.width, height: 14),
            font: .systemFont(ofSize: 8),
            color: .secondaryLabel
        )
    }

    func drawReport(_ report: MetricsReportData) {
        drawText(
            "Metrics report",
            font: .systemFont(ofSize: 26, weight: .bold),
            color: .label,
            spacingAfter: 4
        )
        drawText(
            "Generated \(report.generatedAt.formatted(date: .abbreviated, time: .shortened))",
            font: .systemFont(ofSize: 10),
            color: .secondaryLabel,
            spacingAfter: 20
        )

        drawScope(report)
        drawSectionTitle("Summary")
        drawSummary(report)
        drawSectionTitle("Activity")
        drawText(
            "\(report.activityCounts[.expense] ?? 0) expenses   \(report.activityCounts[.income] ?? 0) income   \(report.activityCounts[.transfer] ?? 0) transfers   \(report.entryCount) total entries",
            font: .systemFont(ofSize: 11),
            color: .label,
            spacingAfter: 18
        )
        drawSectionTitle("Spending by category")

        if report.categories.isEmpty {
            drawText(
                "No included expense activity was recorded in this range.",
                font: .systemFont(ofSize: 11),
                color: .secondaryLabel,
                spacingAfter: 12
            )
        } else {
            for category in report.categories {
                drawCategory(category)
            }
        }

        drawText(
            "Excluded accounts are omitted from this report, matching the Metrics screen.",
            font: .systemFont(ofSize: 9),
            color: .secondaryLabel,
            spacingAfter: 0
        )
    }

    private func drawScope(_ report: MetricsReportData) {
        ensureSpace(82)
        let box = CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: 70)
        UIColor.systemBlue.withAlphaComponent(0.08).setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 12).fill()

        drawFixed("Period", in: CGRect(x: box.minX + 16, y: box.minY + 12, width: 70, height: 14), font: .systemFont(ofSize: 9, weight: .semibold), color: .secondaryLabel)
        drawFixed(report.periodTitle, in: CGRect(x: box.minX + 92, y: box.minY + 10, width: box.width - 108, height: 18), font: .systemFont(ofSize: 12, weight: .semibold), color: .label)
        drawFixed("Range", in: CGRect(x: box.minX + 16, y: box.minY + 39, width: 70, height: 14), font: .systemFont(ofSize: 9, weight: .semibold), color: .secondaryLabel)
        let normalizedRange = report.dateRange.replacingOccurrences(of: "–", with: "-")
        drawFixed("\(normalizedRange) | \(report.currency.rawValue) | \(report.categoryScope)", in: CGRect(x: box.minX + 92, y: box.minY + 37, width: box.width - 108, height: 18), font: .systemFont(ofSize: 10), color: .label)
        y = box.maxY + 20
    }

    private func drawSummary(_ report: MetricsReportData) {
        ensureSpace(96)
        let box = CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: 84)
        UIColor.secondarySystemBackground.setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 12).fill()

        drawSummaryMetric("Income", value: report.income.formatted, color: .systemGreen, x: box.minX + 16, width: 150, y: box.minY + 16)
        drawSummaryMetric("Expenses", value: report.expenses.formatted, color: .systemRed, x: box.minX + 177, width: 150, y: box.minY + 16)
        drawSummaryMetric("Net", value: Money(currency: report.currency, minorUnits: report.income.minorUnits - report.expenses.minorUnits).formatted, color: .systemBlue, x: box.minX + 338, width: 150, y: box.minY + 16)
        y = box.maxY + 18
    }

    private func drawSummaryMetric(_ title: String, value: String, color: UIColor, x: CGFloat, width: CGFloat, y: CGFloat) {
        drawFixed(title.uppercased(), in: CGRect(x: x, y: y, width: width, height: 14), font: .systemFont(ofSize: 9, weight: .semibold), color: .secondaryLabel)
        drawFixed(value, in: CGRect(x: x, y: y + 21, width: width, height: 24), font: .systemFont(ofSize: 16, weight: .bold), color: color)
    }

    private func drawCategory(_ category: MetricsReportCategory) {
        ensureSpace(42)
        let row = CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: 34)
        drawFixed(category.title, in: CGRect(x: row.minX, y: row.minY, width: 300, height: 17), font: .systemFont(ofSize: 11, weight: .semibold), color: .label)
        drawFixed("\(category.count) entr\(category.count == 1 ? "y" : "ies") - \(category.percentage)% of expenses", in: CGRect(x: row.minX, y: row.minY + 18, width: 300, height: 14), font: .systemFont(ofSize: 9), color: .secondaryLabel)
        drawFixed(category.amount.formatted, in: CGRect(x: row.maxX - 150, y: row.minY + 5, width: 150, height: 18), font: .systemFont(ofSize: 11, weight: .semibold), color: .label, alignment: .right)
        drawLine(at: row.maxY + 5)
        y = row.maxY + 12
    }

    private func drawSectionTitle(_ title: String) {
        ensureSpace(30)
        drawText(title, font: .systemFont(ofSize: 16, weight: .bold), color: .label, spacingAfter: 10)
    }

    private func drawText(_ text: String, font: UIFont, color: UIColor, spacingAfter: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: contentRect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let height = max(1, ceil(measured.height))
        ensureSpace(height + spacingAfter)
        drawFixed(
            text,
            in: CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: height),
            font: font,
            color: color
        )
        y += height + spacingAfter
    }

    private func drawFixed(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    private func ensureSpace(_ requiredHeight: CGFloat) {
        guard y + requiredHeight <= pageRect.maxY - 54 else {
            finishPage()
            beginPage()
            return
        }
    }

    private func drawLine(at yPosition: CGFloat? = nil) {
        let lineY = yPosition ?? y
        UIColor.separator.setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: contentRect.minX, y: lineY))
        path.addLine(to: CGPoint(x: contentRect.maxX, y: lineY))
        path.lineWidth = 0.5
        path.stroke()
    }
}
