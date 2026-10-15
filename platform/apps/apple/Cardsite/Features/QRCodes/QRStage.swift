import SwiftUI
import StudioKit

/// The QR stage, as in the Photos editor: the code large and centred on an
/// opaque white sheet of paper, the name in the display face underneath and
/// the type as a quiet label. Used by the builder (live preview) and the
/// viewer (stored image), so a code looks the same in both.
///
/// Nothing translucent ever sits over the code: it has to scan.
/// How big a ``QRStage`` draws.
enum QRStageScale {
    /// The iPhone builder header.
    case compact
    /// The builder's stage column on iPad and Mac.
    case regular
    /// The viewer.
    case large
}

struct QRStage<Footer: View>: View {
    typealias Scale = QRStageScale

    let png: Data?
    var isTransparent = false
    var isLoading = false
    var isEmpty = false
    let title: String
    var isTitlePlaceholder = false
    let typeLabel: String
    let typeSymbol: String
    var scale: Scale = .regular
    let accessibilityLabel: Text
    var accessibilityValue: Text = Text("")
    private let footer: Footer

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        png: Data?,
        isTransparent: Bool = false,
        isLoading: Bool = false,
        isEmpty: Bool = false,
        title: String,
        isTitlePlaceholder: Bool = false,
        typeLabel: String,
        typeSymbol: String,
        scale: Scale = .regular,
        accessibilityLabel: Text,
        accessibilityValue: Text = Text(""),
        @ViewBuilder footer: () -> Footer
    ) {
        self.png = png
        self.isTransparent = isTransparent
        self.isLoading = isLoading
        self.isEmpty = isEmpty
        self.title = title
        self.isTitlePlaceholder = isTitlePlaceholder
        self.typeLabel = typeLabel
        self.typeSymbol = typeSymbol
        self.scale = scale
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: scale == .compact ? StudioSpace.s3 : StudioSpace.s5) {
            QRPaper(padding: paperPadding) {
                QRArtwork(png: png, isTransparent: isTransparent, isLoading: isLoading, isEmpty: isEmpty)
            }
            .frame(maxWidth: Self.artworkWidth(for: scale))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(.isImage)

            VStack(spacing: StudioSpace.s2) {
                Text(title)
                    .studioText(titleStyle)
                    .foregroundStyle(isTitlePlaceholder ? Color.studioText4 : Color.studioText)
                    .multilineTextAlignment(.center)
                    .lineLimit(scale == .large ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                // The type as written ("WiFi", "vCard"): the uppercase label
                // styles would mangle it.
                Label {
                    Text(typeLabel)
                } icon: {
                    Image(systemName: typeSymbol)
                        .accessibilityHidden(true)
                }
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
                footer
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var titleStyle: StudioTextStyle {
        switch scale {
        case .compact: return .titleSm
        case .regular: return .title
        case .large: return dynamicTypeSize.isAccessibilitySize ? .title : .display
        }
    }

    private var paperPadding: CGFloat {
        switch scale {
        case .compact: return StudioSpace.s4
        case .regular: return StudioSpace.s6
        case .large: return StudioSpace.s8
        }
    }

    /// The widest the paper grows, padding included.
    static func artworkWidth(for scale: Scale) -> CGFloat {
        switch scale {
        case .compact: return StudioSpace.s16 * 3 + StudioSpace.s8
        case .regular: return StudioSpace.s16 * 6
        case .large: return CardsiteMeasure.narrow.width
        }
    }
}

extension QRStage where Footer == EmptyView {
    init(
        png: Data?,
        isTransparent: Bool = false,
        isLoading: Bool = false,
        isEmpty: Bool = false,
        title: String,
        isTitlePlaceholder: Bool = false,
        typeLabel: String,
        typeSymbol: String,
        scale: Scale = .regular,
        accessibilityLabel: Text,
        accessibilityValue: Text = Text("")
    ) {
        self.init(png: png, isTransparent: isTransparent, isLoading: isLoading, isEmpty: isEmpty,
                  title: title, isTitlePlaceholder: isTitlePlaceholder, typeLabel: typeLabel,
                  typeSymbol: typeSymbol, scale: scale, accessibilityLabel: accessibilityLabel,
                  accessibilityValue: accessibilityValue) { EmptyView() }
    }
}

/// White paper for a QR code, in every appearance: the code keeps the
/// colours the user chose and the contrast a scanner needs, dark mode or
/// not. The subtree resolves Studio tokens in their light values, so the
/// skeleton and placeholder read correctly on white.
struct QRPaper<Content: View>: View {
    var padding: CGFloat = StudioSpace.s6
    var radius: CGFloat = StudioRadius.xl
    var elevated = true
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .background(Color.StudioPalette.neutral0, in: shape)
            .overlay(shape.strokeBorder(Color.studioBorder, lineWidth: 0.5))
            .environment(\.colorScheme, .light)
            .studioElevation(elevated ? .raised : .flat)
    }
}

#Preview("Stage") {
    ScrollView {
        VStack(spacing: StudioSpace.s10) {
            QRStage(png: QRCodesPreviewData.codes[0].pngData, title: "Window menu",
                    typeLabel: "URL", typeSymbol: "link", scale: .regular,
                    accessibilityLabel: Text("QR code preview"))
            QRStage(png: nil, isEmpty: true, title: "Untitled", isTitlePlaceholder: true,
                    typeLabel: "WiFi", typeSymbol: "wifi", scale: .compact,
                    accessibilityLabel: Text("QR code preview"))
        }
        .padding(StudioSpace.s6)
    }
    .background(Color.studioCanvasBg)
}
