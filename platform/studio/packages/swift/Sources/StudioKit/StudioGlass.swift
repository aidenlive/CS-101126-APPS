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
   panel, never edge-to-edge, never the content layer.
 · The sidebar is not glass. It is a flush edge panel.

 Reduce Transparency wins over every path, including Liquid Glass: with it
 on, the shape is filled with the opaque `surface` token and drawn with the
 `border` hairline, so text over it keeps full contrast whatever scrolls
 underneath.
 */

public extension View {

    /// Applies the Studio glass material, clipped to a rounded rectangle.
    ///
    ///     HStack { … }
    ///         .padding(.horizontal, StudioSpace.s4)
    ///         .studioGlass(cornerRadius: StudioRadius.pill)
    func studioGlass(cornerRadius: CGFloat = StudioRadius.pill) -> some View {
        modifier(StudioGlassModifier(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: nil,
            interactive: false
        ))
    }

    /// Tinted glass. `tint` is the one sanctioned colour moment — pass
    /// `.studioAccent` for a create affordance and nothing else; a tinted
    /// bar or panel reads as an alert. `interactive` belongs only on views
    /// that respond to touch, where the material reacts under the finger.
    func studioGlass(
        cornerRadius: CGFloat = StudioRadius.pill,
        tint: Color?,
        interactive: Bool = false
    ) -> some View {
        modifier(StudioGlassModifier(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: tint,
            interactive: interactive
        ))
    }

    /// Interactive glass without a tint, for pressable chrome.
    func studioGlass(cornerRadius: CGFloat = StudioRadius.pill, interactive: Bool) -> some View {
        modifier(StudioGlassModifier(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: nil,
            interactive: interactive
        ))
    }

    /// Glass in an arbitrary silhouette — a `Circle` for a floating action,
    /// a `Capsule`, or any shape the radius ramp doesn't cover.
    func studioGlass<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(StudioGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }
}

/*
 Generic over the silhouette rather than erasing it to `AnyShape`: the
 fallback draws its ring with `strokeBorder`, which needs `InsettableShape`,
 and an inset stroke keeps the 0.5pt hairline inside the material instead
 of bleeding half a point outside it.
 */
private struct StudioGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            // Opaque surface: no material, no blur, nothing showing through.
            // A tint survives as a solid fill so a create affordance still
            // reads as the accent.
            content
                .background(shape.fill(tint ?? Color.studioSurface))
                .overlay(shape.strokeBorder(Color.studioBorderStrong, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 6)
        } else {
            translucent(content)
        }
    }

    @ViewBuilder
    private func translucent(_ content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            // A tinted affordance keeps its glow on the fallback path too.
            // Resolved to concrete Colors first to keep the chain cheap
            // for the type-checker.
            let glow: Color = tint?.opacity(0.4) ?? .clear
            let wash: Color = tint?.opacity(0.85) ?? .clear

            content
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill(wash))
                .overlay(
                    // The 0.5px translucent ring that separates glass from
                    // whatever sits behind it.
                    shape.strokeBorder(Color.studioGlassBorder, lineWidth: 0.5)
                )
                // Soft drop plus a tight contact shadow — the two-layer
                // treatment from the --glass-shadow token.
                .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 12)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                .shadow(color: glow, radius: 6, x: 0, y: 3)
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var glass: Glass {
        var g: Glass = .regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

// MARK: - Grouping and morphing

/*
 Neighbouring pieces of glass should blend and morph as one body rather
 than animate as separate rectangles. That needs a container that knows
 the cluster, and stable identities so the system can interpolate.

 Wrap a cluster in `StudioGlassContainer` and give each member a
 `.studioGlassMorph(id:in:)`. Both are pass-throughs below 26, where the
 material fallback renders per element, and under Reduce Transparency,
 where each element is already an opaque surface.
 */

/// Groups glass children so they blend and morph as one.
public struct StudioGlassContainer<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = StudioSpace.s2, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

public extension View {
    /// A stable morph identity, so glass animates as liquid between
    /// states. IDs must be unique within their namespace and stable
    /// across renders.
    @ViewBuilder
    func studioGlassMorph(id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
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
