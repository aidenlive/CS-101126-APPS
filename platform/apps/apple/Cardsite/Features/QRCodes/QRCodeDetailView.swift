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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: StudioSpace.s6) {
                StudioCard(radius: StudioRadius.xl) {
                    QRImage(code: code)
                        .padding(StudioSpace.s4)
                        .readableWidth(.narrow)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("QR code for \(code.name)"))
                        .accessibilityValue(Text(verbatim: code.target ?? ""))
                }

                VStack(spacing: StudioSpace.s3) {
                    // The type as written ("WiFi", "vCard"): the uppercase
                    // kicker style would mangle it.
                    Text(typeLabel)
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                    Text(code.name)
                        .studioText(dynamicTypeSize.isAccessibilitySize ? .title : .display)
                        .foregroundStyle(Color.studioText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
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

                // Edit lives in the toolbar; the body keeps the one
                // irreversible action, as the link and resource details do.
                HStack(spacing: StudioSpace.s2) {
                    StudioButton(ResourceVerb.delete.title, systemImage: ResourceVerb.delete.systemImage,
                                 variant: .danger, action: requestDelete)
                    Spacer(minLength: 0)
                }
            }
            .padding(StudioSpace.s6)
            .readableWidth(.reading)
        }
        .background(Color.studioBg)
        .navigationTitle(code.name)
        #if os(iOS) || os(visionOS)
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
                    Text("A dynamic code: change the link’s destination and printed copies follow it.")
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
