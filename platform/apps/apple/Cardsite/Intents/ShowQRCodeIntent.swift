import SwiftUI
import AppIntents
import StudioKit
import CardsiteKit

/// "Show my Cardsite QR code": the code full size in Siri or Shortcuts,
/// ready to be scanned off the screen. App target only.
struct ShowQRCodeIntent: AppIntent {
    static var title: LocalizedStringResource { "Show QR Code" }
    static var description: IntentDescription? {
        IntentDescription(
            "Shows one of your Cardsite QR codes, ready to scan.",
            categoryName: "QR Codes"
        )
    }

    @Parameter(title: "QR Code")
    var qrCode: QRCodeEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$qrCode)")
    }

    init() {}

    init(qrCode: QRCodeEntity) {
        self.qrCode = qrCode
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // The app may have been launched in the background for this.
        StudioFonts.register()
        let session = try await IntentSession.open()
        let (png, design) = try await QRImageCache.image(for: qrCode.id, in: session)
        let code = design.map { QRCodeEntity($0) } ?? qrCode
        return .result(
            dialog: IntentDialog("Here's \(code.name)."),
            view: QRCodeSnippetView(name: code.name, target: code.target, png: png)
        )
    }
}

/// The code on a white quiet zone, its name and what it opens.
struct QRCodeSnippetView: View {
    let name: String
    let target: String?
    let png: Data

    var body: some View {
        VStack(spacing: StudioSpace.s3) {
            if let image = Image(pngData: png) {
                image
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(StudioSpace.s3)
                    // Scanners need a light quiet zone in every appearance:
                    // the palette's white, not the themed surface.
                    .background(Color.StudioPalette.neutral0,
                                in: RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous))
                    .frame(maxWidth: 280)
                    .accessibilityLabel(Text("QR code"))
                    .accessibilityValue(Text(verbatim: target ?? name))
            }
            VStack(spacing: StudioSpace.s1) {
                Text(name)
                    .studioText(.titleSm)
                    .foregroundStyle(Color.studioText)
                    .multilineTextAlignment(.center)
                if let target, !target.isEmpty {
                    Text(verbatim: target)
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(StudioSpace.s4)
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("QR snippet") {
    QRCodeSnippetView(name: "Spring menu", target: "https://card.site/spring-menu",
                      png: QRCodePNG.decode(QRSnippetPreview.dataURL) ?? Data())
        .onAppear { StudioFonts.register() }
}

/// A 1×1 PNG, enough to lay the snippet out in a preview.
private enum QRSnippetPreview {
    static let dataURL = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGP4DwABAQEAWk1v8QAAAABJRU5ErkJggg=="
}
#endif
