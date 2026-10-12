import SwiftUI
import UniformTypeIdentifiers
import StudioKit

/// Share the PNG, save it to a file, and copy what the code encodes.
/// Wraps to a column when the row doesn't fit (narrow panes, large text).
struct QRExportActions: View {
    let png: Data
    let fileName: String
    let title: String
    let copyText: String?
    let copyTitle: String

    @State private var isExporting = false
    @State private var copied = false
    @State private var exportError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s2) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: StudioSpace.s2) { buttons }
                VStack(alignment: .leading, spacing: StudioSpace.s2) { buttons }
            }
            FormErrorText(message: exportError)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fileExporter(
            isPresented: $isExporting,
            item: PNGFile(data: png, name: fileName),
            contentTypes: [.png],
            defaultFilename: fileName
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            } else {
                exportError = nil
                Haptics.success()
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        ShareLink(item: PNGFile(data: png, name: fileName),
                  preview: SharePreview(title, image: Image(pngData: png) ?? Image(systemName: "qrcode"))) {
            Label("Share Image", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.borderedProminent)

        Button {
            isExporting = true
        } label: {
            Label("Save Image…", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.bordered)

        if let copyText, !copyText.isEmpty {
            Button {
                Pasteboard.copy(copyText)
                Haptics.success()
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                Label(copied ? String(localized: "Copied") : copyTitle,
                      systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
    }
}
