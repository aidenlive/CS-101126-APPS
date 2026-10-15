import SwiftUI
import StudioKit
import CardsiteKit

/*
 The bio page canvas: its floating tool palette, the device widths an
 artboard takes on iPad and Mac, and the page's theme as a list thumbnail.

 The palette is chrome, so it is the one piece of Liquid Glass on the
 canvas. It never sits over the artboard on iPad and Mac (it is a rail in
 its own column on the canvas ground); on iPhone the canvas is full-bleed
 and the palette floats over its bottom edge, where the preview's scroll
 view is inset so the page's last block can still scroll clear of it.
 */

// MARK: - Tools

/// What the palette offers, in its order.
enum PageCanvasTool: String, CaseIterable, Hashable, Sendable {
    case add, blocks, theme, settings, share

    var title: String {
        switch self {
        case .add: return String(localized: "Add Block")
        case .blocks: return String(localized: "Blocks")
        case .theme: return String(localized: "Theme")
        case .settings: return String(localized: "Page Settings")
        case .share: return String(localized: "Share and Open")
        }
    }

    /// The one-word caption under the icon on the regular-width rail.
    var caption: String {
        switch self {
        case .add: return String(localized: "Add")
        case .blocks: return String(localized: "Blocks")
        case .theme: return String(localized: "Theme")
        case .settings: return String(localized: "Settings")
        case .share: return String(localized: "Share")
        }
    }

    var systemImage: String {
        switch self {
        case .add: return "plus"
        case .blocks: return "square.stack.3d.up"
        case .theme: return "paintpalette"
        case .settings: return "slider.horizontal.3"
        case .share: return "square.and.arrow.up"
        }
    }
}

/// The floating glass palette. A row at the bottom of the iPhone canvas;
/// a vertical rail with captions on iPad and Mac.
///
/// Add stands apart from the other tools: it is the canvas's one primary
/// action. While the page has no blocks it is accent-tinted and, on
/// iPhone, widens into an "Add Block" capsule, morphing back to a circle
/// once the first block lands (a cross-fade under Reduce Motion).
struct PageToolPalette<Outline: View>: View {
    let page: BioPage
    let isVertical: Bool
    let isEmpty: Bool
    let selected: PageCanvasTool?
    /// The Blocks popover on iPad and Mac, anchored to the Blocks tool.
    /// Nil on iPhone, where Blocks opens a sheet through `perform`.
    var outlinePopover: Binding<Bool>? = nil
    let perform: (PageCanvasTool) -> Void
    @ViewBuilder var outline: () -> Outline

    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        StudioGlassContainer(spacing: StudioSpace.s3) {
            stack {
                addButton
                stack {
                    toolButton(.blocks)
                        .modifier(OutlinePopover(isPresented: outlinePopover, content: outline))
                    toolButton(.theme)
                    toolButton(.settings)
                    shareMenu
                }
                .padding(StudioSpace.s1)
                .studioGlass(cornerRadius: StudioRadius.pill)
                .paletteMorph("tools", in: glass, enabled: !reduceMotion)
            }
        }
        .animation(reduceMotion ? StudioAnimation.base : StudioAnimation.spring, value: isEmpty)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tools"))
    }

    @ViewBuilder
    private func stack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if isVertical {
            VStack(spacing: StudioSpace.s1) { content() }
        } else {
            HStack(spacing: StudioSpace.s1) { content() }
        }
    }

    /// "Add Block" as a capsule while the page is empty on iPhone; a circle
    /// otherwise. Both share one glass identity, so the shape morphs.
    @ViewBuilder
    private var addButton: some View {
        let isWide = isEmpty && !isVertical
        let tint: Color? = isEmpty ? Color.studioAccent : nil
        Button {
            perform(.add)
        } label: {
            Group {
                if isWide {
                    Label(PageCanvasTool.add.title, systemImage: PageCanvasTool.add.systemImage)
                        .labelStyle(.titleAndIcon)
                        .studioText(.ui)
                        .fontWeight(.semibold)
                        .padding(.horizontal, StudioSpace.s4)
                        .frame(minHeight: StudioLayout.tapTarget)
                        .transition(.opacity)
                } else {
                    PageToolLabel(tool: .add, isSelected: selected == .add, showsCaption: isVertical,
                                  isProminent: isEmpty)
                        .transition(.opacity)
                }
            }
            .foregroundStyle(isEmpty ? Color.studioAccentInk : Color.studioText)
            .contentShape(Capsule())
        }
        .buttonStyle(StudioPressStyle(scale: 0.94))
        .studioGlass(in: Capsule(), tint: tint, interactive: true)
        .paletteMorph("add", in: glass, enabled: !reduceMotion)
        .accessibilityLabel(Text(PageCanvasTool.add.title))
        .accessibilityHint(isEmpty ? Text("This page has no blocks yet.") : Text(verbatim: ""))
        .help(PageCanvasTool.add.title)
        .accessibilityIdentifier("page.editor.add")
    }

    private func toolButton(_ tool: PageCanvasTool) -> some View {
        Button {
            perform(tool)
        } label: {
            PageToolLabel(tool: tool, isSelected: selected == tool, showsCaption: isVertical)
        }
        .buttonStyle(StudioPressStyle(scale: 0.92))
        .accessibilityLabel(Text(tool.title))
        .accessibilityAddTraits(selected == tool ? [.isSelected] : [])
        .help(tool.title)
    }

    private var shareMenu: some View {
        Menu {
            PageShareItems(page: page)
        } label: {
            PageToolLabel(tool: .share, isSelected: false, showsCaption: isVertical)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text(PageCanvasTool.share.title))
        .help(PageCanvasTool.share.title)
    }
}

/// The Blocks popover, when there is one.
private struct OutlinePopover<Outline: View>: ViewModifier {
    let isPresented: Binding<Bool>?
    let content: () -> Outline

    func body(content view: Content) -> some View {
        if let isPresented {
            view.popover(isPresented: isPresented, arrowEdge: .leading) {
                content()
            }
        } else {
            view
        }
    }
}

/// One tool: its symbol in a 44 pt target, an accent-soft fill when
/// selected, and a one-word caption under it on the rail.
private struct PageToolLabel: View {
    let tool: PageCanvasTool
    let isSelected: Bool
    let showsCaption: Bool
    var isProminent = false

    var body: some View {
        VStack(spacing: StudioSpace.s1) {
            Image(systemName: tool.systemImage)
                .imageScale(.large)
                .fontWeight(isSelected || isProminent ? .semibold : .regular)
                .frame(width: StudioLayout.tapTarget, height: StudioLayout.tapTarget)
                .background {
                    if isSelected {
                        Circle().fill(Color.studioAccentSoft)
                    }
                }
            if showsCaption {
                // A one-word label, so the uppercase style is right here.
                Text(tool.caption)
                    .studioText(.meta)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.bottom, StudioSpace.s1)
            }
        }
        .foregroundStyle(isProminent ? Color.studioAccentInk : (isSelected ? Color.studioText : Color.studioText2))
        .padding(.horizontal, showsCaption ? StudioSpace.s1 : 0)
        .contentShape(Rectangle())
    }
}

private extension View {
    /// A glass morph identity, left off under Reduce Motion so state changes
    /// cross-fade instead of flowing.
    @ViewBuilder
    func paletteMorph(_ id: String, in namespace: Namespace.ID, enabled: Bool) -> some View {
        if enabled {
            studioGlassMorph(id: id, in: namespace)
        } else {
            self
        }
    }
}

// MARK: - Device widths

/// The artboard's width on iPad and Mac: a phone (390 pt, the width most
/// visitors see) or a portrait tablet. It narrows to fit the window.
enum PageCanvasDevice: String, CaseIterable, Hashable, Sendable {
    case phone, tablet

    var width: CGFloat {
        switch self {
        case .phone: return 390
        case .tablet: return 768
        }
    }

    var title: String {
        switch self {
        case .phone: return String(localized: "Phone width")
        case .tablet: return String(localized: "Tablet width")
        }
    }

    var systemImage: String {
        switch self {
        case .phone: return "iphone"
        case .tablet: return "ipad"
        }
    }
}

/// The phone / tablet switch under the artboard: a small glass pill on the
/// canvas ground, never over the page.
struct PageDeviceToggle: View {
    @Binding var device: PageCanvasDevice

    var body: some View {
        HStack(spacing: StudioSpace.s1) {
            ForEach(PageCanvasDevice.allCases, id: \.self) { option in
                Button {
                    device = option
                } label: {
                    Image(systemName: option.systemImage)
                        .imageScale(.medium)
                        .frame(width: StudioLayout.tapTarget, height: StudioLayout.tapTarget)
                        .foregroundStyle(device == option ? Color.studioText : Color.studioText2)
                        .background {
                            if device == option {
                                Circle().fill(Color.studioAccentSoft)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(StudioPressStyle(scale: 0.92))
                .accessibilityLabel(Text(option.title))
                .accessibilityAddTraits(device == option ? [.isSelected] : [])
                .help(option.title)
            }
        }
        .padding(StudioSpace.s1)
        .studioGlass(cornerRadius: StudioRadius.pill)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Preview width"))
    }
}

// MARK: - First block

/// The empty page's prompt, on an opaque Studio surface: what to do, as a
/// button that opens the block library.
struct PageFirstBlockCallout: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: StudioSpace.s3) {
                Image(systemName: "square.stack.3d.up")
                    .imageScale(.large)
                    .foregroundStyle(Color.studioAccentLine)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    Text("Add your first block")
                        .studioText(.ui)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.studioText)
                    Text("Pick one from the library. It appears on your page as soon as it’s added.")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(StudioSpace.s4)
            .frame(maxWidth: CardsiteMeasure.narrow.width, alignment: .leading)
            .background(Color.studioSurface, in: RoundedRectangle(cornerRadius: StudioRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioRadius.lg, style: .continuous)
                    .strokeBorder(Color.studioBorder, lineWidth: 0.5)
            )
            .studioElevation(.raised)
            .contentShape(Rectangle())
        }
        .buttonStyle(StudioPressStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Theme thumbnail

/// A page's own colours, read from its settings, for the list thumbnail.
/// These are the user's data (hex strings), not design tokens.
struct PageTheme {
    enum Background {
        case color(Color)
        case gradient(Color, Color)
        case none
    }

    let background: Background
    let text: Color?
    let button: Color?

    init(settings: [String: JSONValue]) {
        func color(_ key: String) -> Color? {
            settings[key]?.stringValue.flatMap(HexColor.color(from:))
        }
        switch settings["background_type"]?.stringValue {
        case "gradient":
            if let one = color("background_color_one"), let two = color("background_color_two") {
                background = .gradient(one, two)
            } else if let one = color("background_color_one") ?? color("background_color_two") {
                background = .color(one)
            } else {
                background = .none
            }
        case "image":
            // The image itself isn't fetched for a row; its colours still show.
            background = color("background_color").map(Background.color) ?? .none
        default:
            background = color("background_color").map(Background.color) ?? .none
        }
        text = color("text_color")
        button = color("btn_background_color")
    }

    var hasColours: Bool {
        if case .none = background { return text != nil || button != nil }
        return true
    }
}

/// A bio page in miniature: its background, a picture dot and three
/// buttons in its own colours. Without theme colours, the page glyph on a
/// Studio tile. Dimmed while the page is off.
struct PageThumbnailTile: View {
    let page: BioPage
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = StudioSpace.s8

    var body: some View {
        let theme = PageTheme(settings: page.settings)
        let shape = RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous)
        ZStack {
            shape.fill(Color.studioSurface2)
            themeFill(theme.background, in: shape)
            if theme.hasColours {
                miniature(theme)
            } else {
                Image(systemName: "person.crop.square")
                    .imageScale(.medium)
                    .foregroundStyle(page.isEnabled ? Color.studioAccentLine : Color.studioText3)
            }
        }
        .frame(width: side, height: side * 1.3)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.studioBorder, lineWidth: 0.5))
        .saturation(page.isEnabled ? 1 : 0.3)
        .opacity(page.isEnabled ? 1 : 0.7)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func themeFill(_ fill: PageTheme.Background, in shape: RoundedRectangle) -> some View {
        switch fill {
        case .color(let color):
            shape.fill(color)
        case .gradient(let one, let two):
            shape.fill(LinearGradient(colors: [one, two], startPoint: .top, endPoint: .bottom))
        case .none:
            EmptyView()
        }
    }

    private func miniature(_ theme: PageTheme) -> some View {
        let ink = theme.text ?? Color.studioText2
        let button = theme.button ?? ink.opacity(0.35)
        return VStack(spacing: side * 0.09) {
            Circle()
                .fill(ink.opacity(0.85))
                .frame(width: side * 0.26, height: side * 0.26)
            ForEach(0..<3, id: \.self) { _ in
                Capsule()
                    .fill(button)
                    .frame(width: side * 0.62, height: side * 0.1)
            }
        }
    }
}
