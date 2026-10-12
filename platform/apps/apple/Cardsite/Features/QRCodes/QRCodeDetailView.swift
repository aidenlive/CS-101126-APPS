import SwiftUI
import StudioKit
import CardsiteKit

struct QRCodeDetailView: View {
    let code: QRCode
    let requestDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: StudioSpace.s6) {
                StudioCard {
                    QRImage(code: code)
                        .frame(maxWidth: 320)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(Text("QR code for \(code.target ?? code.name)"))
                }

                VStack(alignment: .leading, spacing: StudioSpace.s3) {
                    StudioKicker(String(localized: "Opens"))
                    if let target = code.target, let url = URL(string: target), url.scheme != nil {
                        Link(destination: url) {
                            Text(verbatim: target).studioText(.body).multilineTextAlignment(.leading)
                        }
                    } else {
                        Text(verbatim: code.target ?? "—").studioText(.body)
                    }
                    if let created = code.createdAt {
                        Text("Created \(created.formatted(date: .abbreviated, time: .omitted))")
                            .studioText(.uiSm)
                            .studioMuted()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: StudioSpace.s2) { actions }
                    VStack(alignment: .leading, spacing: StudioSpace.s2) { actions }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("The image is 256 × 256 px, suited to screens and small print.")
                    .studioText(.uiSm)
                    .studioMuted()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(StudioSpace.s6)
            .readableWidth(560)
        }
        .background(Color.studioBg)
        .navigationTitle(code.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private var actions: some View {
        if let png = code.pngData {
            ShareLink(item: PNGFile(data: png, name: code.fileName),
                      preview: SharePreview(code.name, image: Image(pngData: png) ?? Image(systemName: "qrcode"))) {
                Label("Share Image", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
        }
        if let target = code.target {
            Button {
                Pasteboard.copy(target)
                Haptics.success()
            } label: {
                Label("Copy Link", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
        Button(role: .destructive, action: requestDelete) {
            Label("Delete", systemImage: "trash")
        }
        .buttonStyle(.bordered)
    }
}
