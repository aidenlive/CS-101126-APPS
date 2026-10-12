import SwiftUI

/*
 The shell.

 One structure, three widths — the same three the stylesheet uses:

   ≥ 1100pt  flush 256pt sidebar, full labels
   720–1099  flush 76pt icon rail
   < 720     no sidebar; floating glass tab pill + FAB

 The sidebar is the ONE piece of chrome that is not glass: a flush edge
 panel on `bg-edge` with a hairline trailing border. Everything else —
 topbar pills, tab pill, FAB, toasts — floats at the 14pt inset.

 This is deliberately not a NavigationSplitView. The split view brings
 its own chrome, its own toolbar metrics and its own collapse rules,
 none of which match the spec; fighting it costs more than laying out
 two columns.
 */

// MARK: - Nav model

/// One destination in the shell.
public struct StudioNavDestination<Tag: Hashable>: Identifiable {
    public let tag: Tag
    public let title: String
    public let systemImage: String
    /// The fill-weight glyph, used when the destination is current.
    public let selectedSystemImage: String
    public let count: Int?

    public var id: Tag { tag }

    public init(
        tag: Tag,
        title: String,
        systemImage: String,
        selectedSystemImage: String? = nil,
        count: Int? = nil
    ) {
        self.tag = tag
        self.title = title
        self.systemImage = systemImage
        self.selectedSystemImage = selectedSystemImage ?? "\(systemImage).fill"
        self.count = count
    }
}

// MARK: - App shell

/// The adaptive application frame.
///
///     StudioAppShell(
///         selection: $tab,
///         destinations: destinations,
///         brand: "Studio.",
///         onCompose: { … }
///     ) { tab in
///         content(for: tab)
///     }
public struct StudioAppShell<Tag: Hashable, Content: View, Footer: View>: View {
    private let destinations: [StudioNavDestination<Tag>]
    private let brand: String
    private let brandGlyph: String
    private let onCompose: (() -> Void)?
    private let composeTitle: String
    private let content: (Tag) -> Content
    private let sidebarFooter: Footer

    @Binding private var selection: Tag
    @Environment(\.studioViewport) private var viewport
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        selection: Binding<Tag>,
        destinations: [StudioNavDestination<Tag>],
        brand: String = "Studio.",
        brandGlyph: String = "S",
        composeTitle: String = "Compose",
        onCompose: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Tag) -> Content,
        @ViewBuilder sidebarFooter: () -> Footer
    ) {
        self._selection = selection
        self.destinations = destinations
        self.brand = brand
        self.brandGlyph = brandGlyph
        self.composeTitle = composeTitle
        self.onCompose = onCompose
        self.content = content
        self.sidebarFooter = sidebarFooter()
    }

    public var body: some View {
        HStack(spacing: 0) {
            if viewport.hasSidebar {
                sidebar
                    .frame(width: viewport.isRail ? StudioLayout.sidebarRail : StudioLayout.sidebarFull)
                    // Reduce Motion: the sidebar fades in place, no slide.
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .leading))
            }

            ZStack(alignment: .bottom) {
                Color.studioBg.ignoresSafeArea()

                content(selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !viewport.hasSidebar {
                    tabBar
                        .padding(.bottom, StudioLayout.floatInset)
                }
            }
        }
        .animation(reduceMotion ? nil : StudioAnimation.base, value: viewport)
        .background(Color.studioBgEdge.ignoresSafeArea())
    }

    // MARK: sidebar

    private var isRail: Bool { viewport.isRail }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s2) {
            brandRow
                .padding(.bottom, StudioSpace.s2)

            if let onCompose {
                StudioComposeButton(composeTitle, isCompact: isRail, action: onCompose)
                    .padding(.horizontal, isRail ? 0 : StudioSpace.s3)
                    .padding(.bottom, StudioSpace.s2)
            }

            ForEach(destinations) { destination in
                StudioNavItem(
                    destination: destination,
                    isCurrent: destination.tag == selection,
                    isRail: isRail
                ) {
                    withAnimation(StudioAnimation.base) { selection = destination.tag }
                }
            }

            Spacer(minLength: StudioSpace.s6)

            sidebarFooter
        }
        .padding(.horizontal, isRail ? StudioSpace.s2 : StudioSpace.s3)
        .padding(.vertical, StudioSpace.s5)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.studioBgEdge)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.studioBorder)
                .frame(width: 0.5)
                .ignoresSafeArea()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Primary")
    }

    private var brandRow: some View {
        HStack(spacing: StudioSpace.s3) {
            Text(brandGlyph)
                .font(.custom(StudioFontFamily.display, size: 15))
                .frame(width: 32, height: 32)
                .foregroundStyle(Color.studioSurface)
                .background(
                    RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous)
                        .fill(Color.studioText)
                )
            if !isRail {
                Text(brand)
                    .font(.custom(StudioFontFamily.display, size: 19))
                    .foregroundStyle(Color.studioText)
            }
        }
        .frame(maxWidth: .infinity, alignment: isRail ? .center : .leading)
        .padding(.horizontal, isRail ? 0 : StudioSpace.s3)
        .accessibilityLabel(brand)
    }

    // MARK: mobile tab pill

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(destinations) { destination in
                Button {
                    withAnimation(reduceMotion ? nil : StudioAnimation.spring) { selection = destination.tag }
                } label: {
                    Image(systemName: destination.tag == selection
                          ? destination.selectedSystemImage
                          : destination.systemImage)
                        .font(.system(size: 20))
                        .frame(width: 52, height: 44)
                        .foregroundStyle(destination.tag == selection
                                         ? Color.studioAccentInk
                                         : Color.studioText2)
                        .background {
                            if destination.tag == selection {
                                Capsule().fill(Color.studioAccent)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(StudioPressStyle(scale: 0.92))
                .accessibilityLabel(destination.title)
                .accessibilityAddTraits(destination.tag == selection ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .studioGlass()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Primary")
    }
}

public extension StudioAppShell where Footer == EmptyView {
    init(
        selection: Binding<Tag>,
        destinations: [StudioNavDestination<Tag>],
        brand: String = "Studio.",
        brandGlyph: String = "S",
        composeTitle: String = "Compose",
        onCompose: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Tag) -> Content
    ) {
        self.init(
            selection: selection,
            destinations: destinations,
            brand: brand,
            brandGlyph: brandGlyph,
            composeTitle: composeTitle,
            onCompose: onCompose,
            content: content,
            sidebarFooter: { EmptyView() }
        )
    }
}

// MARK: - Nav item

/// A sidebar row. Current rows take a `surface` fill, the accent mark
/// on the leading edge, and the fill-weight glyph.
public struct StudioNavItem<Tag: Hashable>: View {
    private let destination: StudioNavDestination<Tag>
    private let isCurrent: Bool
    private let isRail: Bool
    private let action: () -> Void

    public init(
        destination: StudioNavDestination<Tag>,
        isCurrent: Bool,
        isRail: Bool = false,
        action: @escaping () -> Void
    ) {
        self.destination = destination
        self.isCurrent = isCurrent
        self.isRail = isRail
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: StudioSpace.s3) {
                Image(systemName: isCurrent ? destination.selectedSystemImage : destination.systemImage)
                    .font(.system(size: 17))
                    .frame(width: 20)
                if !isRail {
                    Text(destination.title).studioText(.ui)
                    Spacer(minLength: 0)
                    if let count = destination.count {
                        Text("\(count)").studioText(.mono).foregroundStyle(Color.studioText3)
                    }
                }
            }
            .foregroundStyle(isCurrent ? Color.studioText : Color.studioText2)
            .padding(.horizontal, isRail ? 0 : StudioSpace.s3)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: isRail ? .center : .leading)
            .background {
                if isCurrent {
                    Capsule().fill(Color.studioSurface).studioElevation(.flat)
                }
            }
            .overlay(alignment: .leading) {
                if isCurrent {
                    Capsule()
                        .fill(Color.studioAccent)
                        .frame(width: 3, height: 20)
                        .offset(x: isRail ? -StudioSpace.s2 : -StudioSpace.s3)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(StudioPressStyle(scale: 0.98))
        .accessibilityLabel(destination.title)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

// MARK: - Topbar

/// The floating chrome row: context pill · spacer · actions · avatar.
///
/// Content scrolls under it, which is why it is glass and why it keeps
/// the float inset on every side. Never edge to edge.
public struct StudioTopbar<Actions: View>: View {
    private let page: String
    private let mark: String
    private let actions: Actions

    public init(page: String, mark: String = "S", @ViewBuilder actions: () -> Actions) {
        self.page = page
        self.mark = mark
        self.actions = actions()
    }

    public var body: some View {
        HStack(spacing: StudioSpace.s2) {
            HStack(spacing: 0) {
                Text(mark)
                    .font(.custom(StudioFontFamily.display, size: 15))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(Color.studioSurface)
                    .background(Color.studioText, in: Circle())

                Rectangle()
                    .fill(Color.studioBorder)
                    .frame(width: 0.5, height: 20)
                    .padding(.horizontal, StudioSpace.s3)

                Text(page)
                    .studioText(.label)
                    .foregroundStyle(Color.studioText)
                    .padding(.trailing, StudioSpace.s3)
            }
            .padding(.horizontal, 8)
            .frame(height: 52)
            .studioGlass()

            Spacer(minLength: StudioSpace.s2)

            actions
        }
        .padding(.horizontal, StudioLayout.floatInset)
        .accessibilityElement(children: .contain)
    }
}

/// A screen: floating topbar over a scrolling content well.
///
/// The padding is the whole point. Content starts BELOW the topbar
/// rather than behind it, and on compact widths it ends above the tab
/// pill — the same two clearances the stylesheet gives `.lk-content`.
/// Getting these wrong is how floating chrome ends up covering the
/// first and last thing on every page.
public struct StudioScreen<Content: View, Actions: View>: View {
    private let page: String
    private let mark: String
    private let content: Content
    private let actions: Actions

    @Environment(\.studioViewport) private var viewport

    public init(
        page: String,
        mark: String = "S",
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        self.page = page
        self.mark = mark
        self.content = content()
        self.actions = actions()
    }

    public var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, viewport.contentPadding)
                    .padding(.top, 76)
                    .padding(.bottom, viewport == .compact ? 96 : StudioSpace.s12)
            }
            .scrollIndicators(.hidden)

            StudioTopbar(page: page, mark: mark) { actions }
                .padding(.top, StudioLayout.floatInset)
        }
    }
}

public extension StudioScreen where Actions == EmptyView {
    init(page: String, mark: String = "S", @ViewBuilder content: () -> Content) {
        self.init(page: page, mark: mark, content: content, actions: { EmptyView() })
    }
}

/// A glass actions pill — the cluster of icon buttons in the topbar.
public struct StudioActionsPill<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: 2) {
            content
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .studioGlass()
    }
}

/// The ⌘K affordance. A button, not a field — it opens search.
public struct StudioSearchPill: View {
    private let placeholder: String
    private let iconOnly: Bool
    private let action: () -> Void

    public init(placeholder: String = "Search Studio\u{2026}", iconOnly: Bool = false, action: @escaping () -> Void) {
        self.placeholder = placeholder
        self.iconOnly = iconOnly
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: StudioSpace.s3) {
                Image(systemName: "magnifyingglass").font(.system(size: 16))
                if !iconOnly {
                    Text(placeholder).studioText(.ui)
                    Spacer(minLength: StudioSpace.s4)
                    StudioKbd("\u{2318}K")
                }
            }
            .foregroundStyle(Color.studioText3)
            .padding(.horizontal, iconOnly ? 0 : StudioSpace.s4)
            .frame(width: iconOnly ? 52 : 240, height: 52)
            .studioGlass()
        }
        .buttonStyle(StudioPressStyle(scale: 0.97))
        .accessibilityLabel("Search")
    }
}

/// The account avatar — the one accent-filled pill in the topbar.
public struct StudioAvatar: View {
    private let initial: String
    private let label: String
    private let action: () -> Void

    public init(initial: String, label: String = "Account menu", action: @escaping () -> Void) {
        self.initial = initial
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(initial)
                .font(.custom(StudioFontFamily.display, size: 16))
                .frame(width: 52, height: 52)
                .foregroundStyle(Color.studioAccentInk)
                .background(Color.studioAccent, in: Circle())
                .studioElevation(.raised)
        }
        .buttonStyle(StudioPressStyle(scale: 0.94))
        .accessibilityLabel(label)
    }
}

/// The sidebar-footer workspace switcher. Collapses to its tile in rail mode.
public struct StudioWorkspaceButton: View {
    private let name: String
    private let meta: String
    private let glyph: String
    private let isRail: Bool
    private let action: () -> Void

    public init(
        name: String,
        meta: String,
        glyph: String = "S",
        isRail: Bool = false,
        action: @escaping () -> Void
    ) {
        self.name = name
        self.meta = meta
        self.glyph = glyph
        self.isRail = isRail
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: StudioSpace.s3) {
                Text(glyph)
                    .font(.custom(StudioFontFamily.display, size: 14))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(Color.studioSurface)
                    .background(
                        RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous)
                            .fill(Color.studioText)
                    )

                if !isRail {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).studioText(.uiSm).foregroundStyle(Color.studioText)
                        Text(meta).studioText(.meta).foregroundStyle(Color.studioText3)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.studioText3)
                }
            }
            .padding(.horizontal, isRail ? 0 : StudioSpace.s2)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                if !isRail {
                    RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
                        .fill(Color.studioSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
                                .strokeBorder(Color.studioBorder, lineWidth: 0.5)
                        )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(StudioPressStyle(scale: 0.98))
        .accessibilityLabel("Switch workspace: \(name)")
    }
}
