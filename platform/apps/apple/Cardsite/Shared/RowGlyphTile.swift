import SwiftUI
import StudioKit

/// The leading tile of a resource row (short links, bio pages): the type's
/// glyph on a neutral Studio tile, as the Studio 1.10 catalogue and list
/// rows draw it (`surface3`, `text2` ink, a continuous rounded square).
///
/// The tile says what kind of thing the row is, never its state: the
/// row's state pill carries Live, Off and Lapsing, and accent stays for
/// actions. An inactive resource only quietens the glyph to `text3`.
/// Side and glyph scale with Dynamic Type, so the row's anatomy holds at
/// every text size.
struct RowGlyphTile: View {
    let systemImage: String
    var isActive = true

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = StudioSpace.s10

    var body: some View {
        Image(systemName: systemImage)
            .studioText(.lead)
            .imageScale(.medium)
            .foregroundStyle(isActive ? Color.studioText2 : Color.studioText3)
            .frame(width: side, height: side)
            .background(Color.studioSurface3, in: RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous))
            .accessibilityHidden(true)
    }
}
