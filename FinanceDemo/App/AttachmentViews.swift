import PDFKit
import SwiftUI
import UIKit

@MainActor
struct AttachmentPreviewView: View {
    @ObservedObject var store: LedgerStore
    let attachment: LedgerAttachment

    var body: some View {
        Group {
            if attachment.contentType == "application/pdf",
               let data = store.attachmentData(for: attachment.id),
               let document = PDFDocument(data: data) {
                AttachmentPDFView(document: document)
            } else if let data = store.attachmentData(for: attachment.id),
                      let image = UIImage(data: data) {
                ScrollView([.vertical, .horizontal]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
            } else {
                ContentUnavailableView(
                    "Attachment unavailable",
                    systemImage: "doc.questionmark",
                    description: Text("The local file is missing or could not be opened.")
                )
            }
        }
        .background(PocketLedgerTheme.background.ignoresSafeArea())
        .navigationTitle(attachment.fileName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AttachmentPDFView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.document = document
    }
}
