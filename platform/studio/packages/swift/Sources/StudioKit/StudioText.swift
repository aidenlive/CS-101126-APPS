import SwiftUI

/*
 Typography.

 The web layer expresses the scale as `.t-*` classes; here it is a view
 modifier over the same generated `StudioTextStyle` values, so both
 platforms read their sizes, weights and tracking from one source.

 Two differences from the web, both deliberate:

 · Display sizes are fluid on the web (`clamp()`); on iOS they scale with
   Dynamic Type instead, which is the platform-correct behaviour.
 · Line height is expressed as `lineSpacing` (the gap BETWEEN lines) rather
   than a multiplier, because that is what SwiftUI takes.
 */

public extension View {

    /// Applies a Studio type style.
    ///
    ///     Text("Library").studioText(.display)
    ///
    /// Set `scaled: false` to opt out of Dynamic Type where a fixed size is
    /// genuinely required — a fixed-size export canvas, for instance.
    func studioText(_ style: StudioTextStyle, scaled: Bool = true) -> some View {
        modifier(StudioTextModifier(style: style, scaled: scaled))
    }

    /// The muted ink used for kickers, metadata and the serif accent word.
    func studioMuted() -> some View {
        foregroundStyle(Color.studioText3)
    }
}

private struct StudioTextModifier: ViewModifier {
    let style: StudioTextStyle
    let scaled: Bool

    @ScaledMetric private var scale: CGFloat = 1
    @Environment(\.studioViewport) private var viewport

    func body(content: Content) -> some View {
        // `@ScaledMetric` is the single Dynamic Type scaler. The font is
        // built with `fixedSize:` because `Font.custom(_:size:)` would
        // scale relative to `.body` a second time (15pt body rendered at
        // ~145pt at AX5), and `scaled: false` would not be fixed at all.
        let size = style.resolvedSize(for: viewport) * (scaled ? scale : 1)

        return content
            .font(.custom(style.family, fixedSize: size))
            .fontWeight(style.weight)
            .tracking(style.tracking * size)
            // lineHeight is a multiplier; SwiftUI wants the extra space only.
            .lineSpacing(max(0, size * (style.lineHeight - 1)))
            .textCase(style.isUppercase ? .uppercase : nil)
    }
}

/// The signature two-tone headline: a display title whose final word is set
/// in the serif italic and dropped to the muted ink.
///
///     StudioTwoToneTitle("A working ", accent: "collection.")
///
/// Keep the accent to ONE word — two reads as a mistake rather than a device.
public struct StudioTwoToneTitle: View {
    private let lead: String
    private let accent: String
    private let style: StudioTextStyle

    @Environment(\.studioViewport) private var viewport

    public init(_ lead: String, accent: String, style: StudioTextStyle = .display) {
        self.lead = lead
        self.accent = accent
        self.style = style
    }

    public var body: some View {
        let size = style.resolvedSize(for: viewport)

        // Concatenating Text keeps this a single laid-out paragraph, so the
        // two faces share a baseline and wrap together.
        return (
            Text(lead)
                .font(.custom(style.family, size: size))
                .fontWeight(style.weight)
            + Text(accent)
                .font(.custom(StudioFontFamily.serif, size: size))
                .italic()
                .foregroundColor(.studioText3)
        )
        .tracking(style.tracking * size)
        .lineSpacing(max(0, size * (style.lineHeight - 1)))
        .fixedSize(horizontal: false, vertical: true)
    }
}

public extension StudioTextStyle {

    /// The point size for a width band.
    ///
    /// The web layer sizes display type with `clamp(min, vw, max)`. iOS
    /// has no viewport unit, so the same two bounds are interpolated
    /// across the three Studio bands instead: a 72pt hero would swamp a
    /// phone, and shipping it at 40pt on a Mac would look timid.
    ///
    /// Non-fluid styles — body, labels, metadata — return their single
    /// size unchanged, exactly as the CSS does.
    func resolvedSize(for viewport: StudioViewport) -> CGFloat {
        guard isFluid else { return size }
        return minSize + (size - minSize) * viewport.fluidProgress
    }
}

/// A kicker with the 5px accent dot.
public struct StudioKicker: View {
    private let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        HStack(spacing: StudioSpace.s2) {
            Circle()
                .fill(Color.studioAccent)
                .frame(width: 5, height: 5)
            Text(text)
                .studioText(.kicker)
                .foregroundStyle(Color.studioText3)
        }
    }
}
