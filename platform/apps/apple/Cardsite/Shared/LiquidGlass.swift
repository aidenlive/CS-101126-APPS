import SwiftUI
import StudioKit

// App-level Liquid Glass helpers. Every iOS/macOS 26 API is gated here once,
// so feature code stays readable and still runs on iOS 18 / macOS 15 with
// the closest earlier look. Glass is for chrome only (HIG: "Don't use Liquid
// Glass in the content layer"); content stays on opaque Studio surfaces.
// Material-level glass (custom floating clusters) comes from StudioKit:
// `.studioGlass(...)`, `StudioGlassContainer`, `.studioGlassMorph(id:in:)`.

/// The glass button styles: `.glass` for secondary floating controls,
/// `.glassProminent` for the one primary action on a surface. Below 26:
/// `.bordered` / `.borderedProminent`.
struct CardsiteGlassButton: ViewModifier {
    var prominent = false

    func body(content: Content) -> some View {
        #if os(visionOS)
        if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        #else
        if #available(iOS 26.0, macOS 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        }
        #endif
    }
}

extension View {
    /// A floating chrome button in the system glass style.
    func glassButton(prominent: Bool = false) -> some View {
        modifier(CardsiteGlassButton(prominent: prominent))
    }

    /// iPhone: the tab bar shrinks to its selected tab while scrolling down
    /// (Music, TV). No effect elsewhere or before iOS 26.
    @ViewBuilder
    func minimizesTabBarOnScroll() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// A hero that extends under a sidebar or inspector (iOS/macOS 26).
    /// One per screen, on imagery or a theme band — never on text.
    @ViewBuilder
    func heroBackgroundExtension() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            backgroundExtensionEffect()
        } else {
            self
        }
    }

    /// A custom bar pinned to an edge that keeps the scroll edge effect
    /// (iOS/macOS 26 `safeAreaBar`); `safeAreaInset` before 26.
    @ViewBuilder
    func edgeBar<Bar: View>(_ edge: VerticalEdge, @ViewBuilder bar: () -> Bar) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            safeAreaBar(edge: edge) { bar() }
        } else {
            safeAreaInset(edge: edge) { bar() }
        }
    }

    /// Mac: a hard scroll edge under the toolbar, as on macOS; iOS keeps the
    /// default soft edge.
    @ViewBuilder
    func platformScrollEdge() -> some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
