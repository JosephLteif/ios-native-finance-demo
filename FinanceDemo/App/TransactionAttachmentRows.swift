import SwiftUI

@MainActor
struct TransactionAttachmentRows: View {
    let attachments: [LedgerAttachment]
    let onPreview: (LedgerAttachment) -> Void
    let onReplace: (LedgerAttachment) -> Void
    let onDelete: (LedgerAttachment) -> Void

    var body: some View {
        ForEach(attachments) { attachment in
            HStack {
                Button {
                    onPreview(attachment)
                } label: {
                    Label(
                        attachment.fileName,
                        systemImage: attachment.contentType == "application/pdf" ? "doc.richtext" : "photo"
                    )
                }
                .foregroundStyle(PocketLedgerTheme.textPrimary)

                Spacer()

                Button("Replace") {
                    onReplace(attachment)
                }
                .font(.footnote.weight(.semibold))
            }
            .swipeActions {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    onDelete(attachment)
                }
            }
        }
    }
}
