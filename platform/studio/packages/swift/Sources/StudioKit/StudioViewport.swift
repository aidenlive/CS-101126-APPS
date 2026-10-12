import SwiftUI

/*
 Viewport.

 The web layer has media queries; SwiftUI does not. Size classes are
 close but not the same thing — an iPad in a 700pt split view reports
 `.regular` while the CSS at that width is already in rail mode.

 So Studio measures the width and maps it through the SAME two
 thresholds the stylesheet uses, `--bp-tablet: 720` and
 `--bp-desktop: 1100`, generated into `StudioLayout`. One number, three
 platforms, no drift.

     .studioViewport()      // measures and publishes down the tree

 Read it anywhere below:

     @Environment(\.studioViewport) private var viewport
 */

/// The three width bands, matching the CSS breakpoints exactly.
public enum StudioViewport: String, CaseIterable, Sendable {
    /// < 720pt — floating tab pill + FAB, no sidebar.
    case compact
    /// 720–1099pt — the 76pt icon rail.
    case medium
    /// ≥ 1100pt — the full 256pt sidebar.
    case expanded

    public init(width: CGFloat) {
        if width < StudioLayout.bpTablet { self = .compact }
        else if width < StudioLayout.bpDesktop { self = .medium }
        else { self = .expanded }
    }

    /// True where the shell shows a sidebar at all.
    public var hasSidebar: Bool { self != .compact }

    /// True where the sidebar is collapsed to its icon rail.
    public var isRail: Bool { self == .medium }

    /// Where a fluid type style sits between its min and max, 0…1.
    /// Mirrors the shape of the CSS `clamp()`: pinned at the bottom
    /// through compact, pinned at the top from desktop up.
    var fluidProgress: CGFloat {
        switch self {
        case .compact: return 0
        case .medium: return 0.5
        case .expanded: return 1
        }
    }
}

private struct StudioViewportKey: EnvironmentKey {
    /// Phone-first: assume the smallest band until something measures.
    static let defaultValue: StudioViewport = .compact
}

public extension EnvironmentValues {
    var studioViewport: StudioViewport {
        get { self[StudioViewportKey.self] }
        set { self[StudioViewportKey.self] = newValue }
    }
}

public extension View {

    /// Measures this view's width and publishes the matching band to
    /// every descendant. Apply it once, at the root of a scene.
    func studioViewport() -> some View {
        modifier(StudioViewportReader())
    }

    /// Publishes a band directly — for previews, snapshot tests, or a
    /// pane that should style itself as though it were narrower.
    func studioViewport(_ viewport: StudioViewport) -> some View {
        environment(\.studioViewport, viewport)
    }
}

private struct StudioViewportReader: ViewModifier {
    @State private var viewport: StudioViewport = .compact

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { update(proxy.size.width) }
                        .onChange(of: proxy.size.width) { _, width in update(width) }
                }
            )
            .environment(\.studioViewport, viewport)
    }

    private func update(_ width: CGFloat) {
        let next = StudioViewport(width: width)
        guard next != viewport else { return }
        viewport = next
    }
}

/*
 Content padding.

 The CSS content well is `clamp(20px, 3vw, 32px)`; these are its two
 ends. Anything that fills the canvas should use this rather than
 picking a spacing step by eye, so the three platforms indent by the
 same amount at the same width.
 */
public extension StudioViewport {
    var contentPadding: CGFloat {
        self == .compact ? StudioSpace.s5 : StudioSpace.s8
    }

    /// The gap between major sections of a page.
    var sectionGap: CGFloat {
        self == .compact ? StudioSpace.s8 : StudioSpace.s10
    }
}
