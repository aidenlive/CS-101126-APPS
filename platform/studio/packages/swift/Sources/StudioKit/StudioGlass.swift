import SwiftUI

/*
 The glass material.

 THIS IS THE ONLY VERSION-SENSITIVE FILE IN THE PACKAGE.

 On iOS 26 and later the system Liquid Glass effect is used directly. Below
 that, the same shape is filled with a SwiftUI material plus the hairline
 border and layered shadow that the design system specifies, which reads
 very close to the real thing.

 If Apple's API surface shifts in a later SDK, this file is the single place
 to update — every component reaches the material through `.studioGlass()`
 and none of them touch the underlying API.

 The rules from DESIGN.md apply here exactly as they do on the web:
 · Glass is for chrome that FLOATS over scrolling content — never a static
   panel, never edge-to-edge.
 · The sidebar is not glass. It is a flush edge panel.
 */

public extension View {

    /// Applies the Studio glass material, clipped to a rounded rectangle.
    ///
    ///     HStack { … }
    ///         .padding(.horizontal, StudioSpace.s4)
    ///         .studioGlass(cornerRadius: StudioRadius.pill)
    func studioGlass(cornerRadius: CGFloat = StudioRadius.pill) -> some View {
        modifier(StudioGlassModifier(cornerRadius: cornerRadius))
    }
}

private struct StudioGlassModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    // The 0.5px translucent ring that separates glass from
                    // whatever sits behind it.
                    shape.strokeBorder(Color.studioGlassBorder, lineWidth: 0.5)
                )
                // Soft drop plus a tight contact shadow — the two-layer
                // treatment from the --glass-shadow token.
                .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 12)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
    }
}

/// The float inset. Every piece of floating chrome sits this far from the
/// safe area, on all sides — never edge-to-edge.
public extension View {
    func studioFloatInset() -> some View {
        padding(StudioLayout.floatInset)
    }
}

/// Elevation for opaque surfaces. Glass has its own shadow; these are the
/// other two tiers.
public enum StudioElevation {
    case flat
    case raised
}

public extension View {
    func studioElevation(_ tier: StudioElevation) -> some View {
        switch tier {
        case .flat:
            return AnyView(shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1))
        case .raised:
            return AnyView(
                shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 6)
                    .shadow(color: .black.opacity(0.07), radius: 1.5, x: 0, y: 1)
            )
        }
    }
}
