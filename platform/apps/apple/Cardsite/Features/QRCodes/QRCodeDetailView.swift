import SwiftUI
import StudioKit
import CardsiteKit

/// One code: the image on a Studio card with generous margins, its name in
/// the display face, what it encodes, and share, save, copy, edit and delete.
struct QRCodeDetailView: View {
    let code: QRCode
    let typeLabel: String
    let edit: () -> Void
    let requestDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: StudioSpace.s6) {
                StudioCard(radius: StudioRadius.xl) {
                    QRImage(code: code)
                        .padding(StudioSpace.s4)
                        .frame(maxWidth: 420)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("QR code for \(code.name)"))
                        .accessibilityValue(Text(verbatim: code.target ?? ""))
                }

                VStack(spacing: StudioSpace.s3) {
                    StudioKicker(typeLabel)
                    Text(code.name)
                        .studioText(.display)
                        .foregroundStyle(Color.studioText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                    if let created = code.createdAt {
                        Text("Created \(created.formatted(date: .abbreviated, time: .omitted))")
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText3)
                    }
                }
                .frame(maxWidth: .infinity)

                encodesCard

                if let png = code.pngData {
                    QRExportActions(png: png, fileName: code.fileName, title: code.name,
                                    copyText: code.target, copyTitle: code.copyTitle)
                }

                HStack(spacing: StudioSpace.s2) {
                    StudioButton(String(localized: "Edit"), systemImage: "pencil", variant: .outline, action: edit)
                    StudioButton(String(localized: "Delete"), systemImage: "trash", variant: .danger, action: requestDelete)
                    Spacer(minLength: 0)
                }
            }
            .padding(StudioSpace.s6)
            .readableWidth(640)
        }
        .background(Color.studioBg)
        .navigationTitle(code.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: edit) {
                    Label("Edit", systemImage: "pencil")
                }
            }
        }
    }

    /// What a scan opens or reads.
    private var encodesCard: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: StudioSpace.s3) {
                StudioKicker(QRCodeCatalog.encodesURL(code.type) ? String(localized: "Opens") : String(localized: "Encodes"))
                if let target = code.target, !target.isEmpty {
                    if QRCodeCatalog.encodesURL(code.type), let url = URL(string: target), url.scheme != nil {
                        Link(destination: url) {
                            Text(verbatim: target)
                                .studioText(.body)
                                .multilineTextAlignment(.leading)
                        }
                    } else {
                        Text(verbatim: target)
                            .studioText(.mono)
                            .foregroundStyle(Color.studioText2)
                            .textSelection(.enabled)
                            .lineLimit(12)
                    }
                } else {
                    Text("Nothing recorded")
                        .studioText(.body)
                        .foregroundStyle(Color.studioText3)
                }
                if code.type == QRCodeCatalog.dynamicURLType {
                    Text("A dynamic code: change the link's destination and printed copies follow it.")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                }
            }
        }
    }
}

#Preview("Detail") {
    NavigationStack {
        QRCodeDetailView(code: QRCodesPreviewData.codes[0], typeLabel: "URL", edit: {}, requestDelete: {})
    }
}

#Preview("WiFi detail") {
    NavigationStack {
        QRCodeDetailView(code: QRCodesPreviewData.codes[1], typeLabel: "WiFi", edit: {}, requestDelete: {})
    }
}
