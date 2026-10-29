import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Pré-visualização de PDF gerado pelo app (relatório de projeto): rolar/zoom pelo `PDFView`,
/// salvar e imprimir.
struct PDFPreviewSheet: View {
    let document: ProjectReportPDFDocument
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PDFKitView(data: document.data)
            Divider()
            HStack {
                Button {
                    print()
                } label: {
                    Label("Imprimir…", systemImage: "printer")
                }
                Spacer()
                Button("Fechar", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button {
                    save()
                } label: {
                    Label("Salvar PDF…", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 680, height: 820)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.fileName
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? document.data.write(to: url, options: .atomic)
    }

    private func print() {
        guard let pdf = PDFDocument(data: document.data),
              let operation = pdf.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true)
        else { return }
        operation.run()
    }
}

/// `PDFView` do PDFKit dentro do SwiftUI.
private struct PDFKitView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .windowBackgroundColor
        view.document = PDFDocument(data: data)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data { view.document = PDFDocument(data: data) }
    }
}
