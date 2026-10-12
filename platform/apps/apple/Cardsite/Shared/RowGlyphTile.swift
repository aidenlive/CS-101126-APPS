import SwiftUI
import StudioKit

/// The leading tile of a resource row (short links, bio pages): the type's
/// glyph on a rounded Studio surface, in accent ink while the resource is
/// live. Scales with Dynamic Type, so the row's anatomy holds at every
/// text size.
struct RowGlyphTile: View {
    let systemImage: String
    var isActive = true

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = StudioSpace.s8

    var body: some View {
        Image(systemName: systemImage)
            .imageScale(.medium)
            .foregroundStyle(isActive ? Color.studioAccentLine : Color.studioText3)
            .frame(width: side, height: side)
            .background(Color.studioSurface2, in: RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous))
            .accessibilityHidden(true)
    }
}
