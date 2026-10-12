import SwiftUI

/*
 Editor shells.

 The two editing surfaces from DESIGN.md, previously web-only:

   Document  a centred measure column under a floating format bar —
             writing, not chrome, owns the screen.
   Canvas    a full-bleed working area on `bg-edge` with three pieces
             of floating glass: a tool rail (leading), an inspector
             (trailing, collapsing to a bottom sheet on compact), and
             a zoom pill (bottom centre).

 Both are shells, not editors: they lay out the chrome and hand the
 working surface to the caller. What edits inside them is the app's
 business.
 */

// MARK: - Document editor

/// A centred writing column with a floating format bar above it.
/// The column caps at the reading measure; the bar is glass and keeps
/// the float inset like every other piece of chrome.
public struct StudioDocumentEditorShell<Toolbar: View, Content: View>: View {
    private let measure: CGFloat
    private let toolbar: Toolbar
    private let content: Content

    @Environment(\.studioViewport) private var viewport

    public init(
        measure: CGFloat = StudioComposition.rhythmMeasure,
        @ViewBuilder toolbar: () -> Toolbar,
        @ViewBuilder content: () -> Content
    ) {
        self.measure = measure
        self.toolbar = toolbar()
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            content
                .frame(maxWidth: measure, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, viewport.contentPadding)
                .padding(.vertical, StudioSpace.s8)
        }
        .scrollIndicators(.hidden)
        .background(Color.studioBg)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 2) { toolbar }
                .padding(.horizontal, StudioSpace.s2)
                .frame(minHeight: StudioLayout.pillHeight)
                .studioGlass()
                .padding(.top, StudioLayout.floatInset)
                .padding(.bottom, StudioSpace.s2)
        }
    }
}

// MARK: - Canvas editor

/// The canvas shell. Chrome floats; the canvas fills everything.
///
///     StudioCanvasShell(
///         tools: { StudioToolButton(…); StudioToolButton(…) },
///         inspector: { InspectorPanels() },
///         zoomLabel: "100%",
///         onZoomIn: { … }, onZoomOut: { … }
///     ) {
///         MyCanvas()
///     }
///
/// On compact widths the inspector collapses behind a glass toggle and
/// presents as a sheet — a 280pt fixed panel on a phone would leave no
/// canvas at all.
public struct StudioCanvasShell<Canvas: View, Tools: View, Inspector: View>: View {
    private let canvas: Canvas
    private let tools: Tools
    private let inspector: Inspector
    private let zoomLabel: String
    private let onZoomIn: (() -> Void)?
    private let onZoomOut: (() -> Void)?

    @Environment(\.studioViewport) private var viewport
    @State private var inspectorShown = false

    public init(
        zoomLabel: String = "100%",
        onZoomIn: (() -> Void)? = nil,
        onZoomOut: (() -> Void)? = nil,
        @ViewBuilder tools: () -> Tools,
        @ViewBuilder inspector: () -> Inspector,
        @ViewBuilder canvas: () -> Canvas
    ) {
        self.zoomLabel = zoomLabel
        self.onZoomIn = onZoomIn
        self.onZoomOut = onZoomOut
        self.tools = tools()
        self.inspector = inspector()
        self.canvas = canvas()
    }

    public var body: some View {
        ZStack {
            // The work plane. Its own token, not --bg-edge: a canvas
            // is not "the page, one step deeper", it is a different
            // kind of ground, and borrowing surface tokens is what
            // made the grid fight the chrome floating over it.
            Color.studioCanvasBg.ignoresSafeArea()

            canvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Tool rail — floating glass, leading edge, vertically centred.
            HStack {
                VStack(spacing: 2) { tools }
                    .padding(4)
                    .studioGlass(cornerRadius: StudioRadius.pill)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Tools")
                Spacer()
            }
            .padding(.leading, StudioLayout.floatInset)

            // Inspector — a fixed glass panel where there is room,
            // a sheet-toggling button where there is not.
            HStack {
                Spacer()
                if viewport == .compact {
                    VStack {
                        Button {
                            inspectorShown = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 17))
                                .frame(width: StudioLayout.tapTarget, height: StudioLayout.tapTarget)
                                .foregroundStyle(Color.studioText2)
                                .studioGlass()
                        }
                        .buttonStyle(StudioPressStyle(scale: 0.94))
                        .accessibilityLabel("Inspector")
                        Spacer()
                    }
                    .padding(.top, StudioSpace.s16)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: StudioSpace.s4) {
                            inspector
                        }
                        .padding(StudioSpace.s4)
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: 280)
                    .frame(maxHeight: 520)
                    .fixedSize(horizontal: false, vertical: true)
                    .studioGlass(cornerRadius: StudioRadius.lg)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Inspector")
                }
            }
            .padding(.trailing, StudioLayout.floatInset)

            // Zoom pill — bottom centre.
            VStack {
                Spacer()
                HStack(spacing: 2) {
                    if let onZoomOut {
                        zoomButton("minus", label: "Zoom out", action: onZoomOut)
                    }
                    Text(zoomLabel)
                        .studioText(.mono)
                        .foregroundStyle(Color.studioText2)
                        .frame(minWidth: 52)
                    if let onZoomIn {
                        zoomButton("plus", label: "Zoom in", action: onZoomIn)
                    }
                }
                .padding(4)
                .studioGlass()
            }
            .padding(.bottom, StudioLayout.floatInset)
        }
        .sheet(isPresented: $inspectorShown) {
            ScrollView {
                VStack(alignment: .leading, spacing: StudioSpace.s4) {
                    inspector
                }
                .padding(StudioSpace.s5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.studioBg)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func zoomButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(Color.studioText2)
                .contentShape(Circle())
        }
        .buttonStyle(StudioPressStyle(scale: 0.9))
        .accessibilityLabel(label)
    }
}

/// One button of the canvas tool rail. Selected tools take the accent
/// soft fill, matching toolbar-button behaviour on the web.
public struct StudioToolButton: View {
    private let systemImage: String
    private let label: String
    private let isSelected: Bool
    private let action: () -> Void

    public init(
        systemImage: String,
        label: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.label = label
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                .frame(width: 44, height: 44)
                .foregroundStyle(isSelected ? Color.studioText : Color.studioText2)
                .background {
                    if isSelected {
                        Circle().fill(Color.studioAccentSoft)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(StudioPressStyle(scale: 0.9))
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The working grid — the visual cue that this surface is a workspace,
/// not a page.
///
/// Two lattices, matching the web canvas exactly: a minor line every
/// `spacing` points and a major one every eighth. Both draw in the
/// `canvasGrid` tokens, which are deliberately WEAKER than
/// `--border`. The previous version drew dots in `Color.studioBorder`
/// — structural hairline strength — so the grid out-contrasted the
/// artwork it was meant to sit behind and every floating panel had to
/// compete with it. A grid is orientation, not structure.
///
/// `scale` rescales the lattice so the grid tracks a zoomed artboard
/// instead of sliding underneath it.
public struct StudioCanvasGrid: View {
    private let spacing: CGFloat
    private let scale: CGFloat

    public init(spacing: CGFloat = 12, scale: CGFloat = 1) {
        self.spacing = spacing
        self.scale = scale
    }

    public var body: some View {
        Canvas { context, size in
            let minor = max(4, spacing * scale)
            let major = minor * 8

            func rule(step: CGFloat, color: Color, width: CGFloat) {
                var path = Path()
                var x: CGFloat = 0
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += step
                }
                context.stroke(path, with: .color(color), lineWidth: width)
            }

            rule(step: minor, color: Color.studioCanvasGrid, width: 0.5)
            rule(step: major, color: Color.studioCanvasGridMajor, width: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// An artboard: content sitting ON the plane.
///
/// ONE separation. The web version used to carry a hairline, a strong
/// border AND a raised shadow for a single edge; this never repeats
/// that. The shadow does the work, and the hairline returns only in
/// light mode where a white artboard on a light plane needs it.
public struct StudioArtboard<Content: View>: View {
    private let content: Content
    @Environment(\.colorScheme) private var colorScheme

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .background(Color.studioCanvasArtboard)
            .clipShape(RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous))
            .overlay {
                if colorScheme == .light {
                    RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous)
                        .strokeBorder(Color.studioBorder, lineWidth: 0.5)
                }
            }
            .studioElevation(.raised)
    }
}
