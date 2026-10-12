import SwiftUI
import StudioKit

/// The one row anatomy for resources (PARITY-PLAN §6): the type's glyph
/// tile, the title with its state pill, a middle-truncated subtitle (the
/// address), an optional detail line, the clicks figure, and a trailing
/// accessory (the on/off switch, a chevron).
///
/// At accessibility text sizes the row stacks: the text gets the full
/// width, addresses wrap instead of truncating to a few characters, and
/// the accessory moves onto its own leading-aligned line under the text.
///
/// In compact width (iPhone) a row that is a navigation link already has
/// the system disclosure chevron, and a switch next to a chevron is not a
/// pattern Apple's lists use, so the trailing accessory is left out there.
/// The state stays visible as the Off / Lapsing pill, and Turn On / Turn
/// Off stays one gesture away in the leading swipe and the context menu
/// (``ResourceActionSet``). At accessibility sizes the switch keeps its
/// own line, where it has the room.
///
///     CardsiteResourceRow(systemImage: "link", isLive: link.isEnabled,
///                         title: Text(verbatim: "card.site/spring-menu"),
///                         subtitle: Text(verbatim: "example.com/menu"),
///                         state: .off, clicks: 1_284) {
///         LiveSwitch(isOn: link.isEnabled) { … }
///     }
struct CardsiteResourceRow<Trailing: View>: View {
    let systemImage: String
    var isLive = true
    let title: Text
    var subtitle: Text? = nil
    var detail: Text? = nil
    /// Shown as a pill when it isn't `.live`: rows only call out the exceptions.
    var state: ResourceState? = nil
    var clicks: Int? = nil
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.dynamicTypeSize) private var typeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var isStacked: Bool { typeSize.isAccessibilitySize }

    /// The accessory is shown in regular width and at accessibility sizes;
    /// left out in a compact, single-line row (see the type's note).
    private var showsTrailing: Bool {
        #if os(iOS)
        return isStacked || sizeClass != .compact
        #else
        return true
        #endif
    }

    var body: some View {
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: StudioSpace.s2))
            : AnyLayout(HStackLayout(spacing: StudioSpace.s3))

        layout {
            RowGlyphTile(systemImage: systemImage, isActive: isLive)

            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                titleLine
                if let subtitle {
                    subtitle
                        .lineLimit(isStacked ? 4 : 1)
                        .truncationMode(.middle)
                }
                if let detail {
                    detail.lineLimit(isStacked ? nil : 2)
                }
                if isStacked, let clicks {
                    ClicksFigure(clicks: clicks)
                }
            }
            .studioText(.uiSm)
            .foregroundStyle(Color.studioText3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if !isStacked, let clicks {
                ClicksFigure(clicks: clicks)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                    .fixedSize()
            }

            if showsTrailing {
                if isStacked {
                    // Its own line, leading, with the text above it.
                    trailing()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    trailing()
                }
            }
        }
        .padding(.vertical, StudioSpace.s1)
    }

    @ViewBuilder
    private var titleLine: some View {
        let pill: StudioStatusPill? = (state == nil || state == .live) ? nil : state?.pill
        if isStacked {
            title
                .studioText(.ui)
                .foregroundStyle(Color.studioText)
                .fixedSize(horizontal: false, vertical: true)
            if let pill { pill }
        } else {
            HStack(spacing: StudioSpace.s2) {
                // One line, truncated in the middle: an address keeps its
                // host and its slug end ("card.site/su…sale") instead of
                // breaking inside a word in a narrow column.
                title
                    .studioText(.ui)
                    .foregroundStyle(Color.studioText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                if let pill { pill.fixedSize() }
            }
        }
    }
}

extension CardsiteResourceRow where Trailing == EmptyView {
    init(systemImage: String, isLive: Bool = true, title: Text, subtitle: Text? = nil, detail: Text? = nil,
         state: ResourceState? = nil, clicks: Int? = nil) {
        self.init(systemImage: systemImage, isLive: isLive, title: title, subtitle: subtitle, detail: detail,
                  state: state, clicks: clicks) { EmptyView() }
    }
}

/// A row's clicks: the grouped figure with the click glyph. "1,284" in a
/// row; display figures (`Int.figure`) are for tiles and headers.
struct ClicksFigure: View {
    let clicks: Int

    var body: some View {
        Label(clicks.grouped, systemImage: "cursorarrow.click")
            .labelStyle(.titleAndIcon)
            .monospacedDigit()
            .accessibilityLabel(Text("\(clicks) clicks"))
    }
}

/// A row's on/off switch: "Live" or "Off" to VoiceOver, small, accent.
struct LiveSwitch: View {
    let isOn: Bool
    var isBusy = false
    let set: @MainActor (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { [isOn] in isOn }, set: { [set] in set($0) })) {
            Text("Status")
        }
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(Color.studioAccent)
        .disabled(isBusy)
        .accessibilityLabel(Text("Status"))
        .accessibilityValue(Text(isOn ? ResourceState.live.title : ResourceState.off.title))
    }
}

#Preview("Resource rows") {
    List {
        CardsiteResourceRow(systemImage: "link", title: Text(verbatim: "card.site/spring-menu"),
                            subtitle: Text(verbatim: "example.com/menu"), state: .live, clicks: 1_284) {
            LiveSwitch(isOn: true) { _ in }
        }
        CardsiteResourceRow(systemImage: "link", isLive: false, title: Text(verbatim: "card.site/launch"),
                            subtitle: Text(verbatim: "example.com"), state: .off, clicks: 0) {
            LiveSwitch(isOn: false) { _ in }
        }
        CardsiteResourceRow(systemImage: "person.text.rectangle", title: Text(verbatim: "Ada Lovelace"),
                            subtitle: Text(verbatim: "card.site/ada"), detail: Text(verbatim: "Analytical Engines Ltd"),
                            state: .lapsing, clicks: 128_400)
    }
    .studioList()
}

#Preview("Resource rows, AX5") {
    List {
        CardsiteResourceRow(systemImage: "link", title: Text(verbatim: "card.site/spring-menu-and-drinks"),
                            subtitle: Text(verbatim: "example.com/menu/spring/2026"), state: .off, clicks: 1_284) {
            LiveSwitch(isOn: false) { _ in }
        }
    }
    .studioList()
    .environment(\.dynamicTypeSize, .accessibility5)
}
