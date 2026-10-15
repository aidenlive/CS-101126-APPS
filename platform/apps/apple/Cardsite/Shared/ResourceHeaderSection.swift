import SwiftUI
import StudioKit

/// The hero at the top of a saved resource's editor, shared by the short
/// link detail and every resource editor (DESIGN-DIRECTION "Editors"):
///
/// - the state pill (and "Saved"), with the type's name where it helps;
/// - the address in display type, wrapping after dots and slashes;
/// - where it leads (the destination's host and path), under it;
/// - the figures: clicks and visitors over 30 days, and all-time clicks;
/// - the actions: Copy Link (the one filled accent button), Open and
///   Card (tonal), plus the type's own. They sit on the content card, so
///   they are opaque Studio controls, not glass (HIG: glass is chrome). On an iPhone they stay one line:
///   everything but Copy Link drops to its symbol before the row wraps.
///
/// Then the Live switch, the caller's rows (Statistics, Create QR Code)
/// and the release-window banner. The hero is content on an opaque Studio
/// row; only its buttons are glass, because they are controls.
///
///     ResourceHeaderSection(
///         state: ResourceState(isEnabled: link.isEnabled, isLapsing: link.isLapsing),
///         title: "card.site/spring-menu", subtitle: "example.com/menu",
///         url: url, cardURL: card,
///         toggle: .init(isOn: link.isEnabled, isBusy: busy, set: { … }),
///         figures: [.init(title: String(localized: "Clicks · all time"), value: 1_284)]
///     ) {
///         // extra hero buttons (Label-based, so they can drop to a symbol)
///     } rows: {
///         NavigationLink(value: route) { ResourceVerb.statistics.label }
///     }
struct ResourceHeaderSection<Actions: View, Rows: View>: View {
    /// Nil for a resource with no address and no switch (a splash page);
    /// `kindLabel` then names the type.
    let state: ResourceState?
    var kindLabel: String? = nil
    var didJustSave = false
    let title: String
    /// A second line in body type under the title (a resource's address,
    /// when the title is its name).
    var address: String? = nil
    /// Where it leads: a destination or checkout, shown as host and path.
    var subtitle: String? = nil
    var url: URL? = nil
    var cardURL: URL? = nil
    var cardHint: String? = nil
    var toggle: ResourceLiveToggle? = nil
    var figures: [ResourceFigure] = []
    var isLapsing = false
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var rows: () -> Rows

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false

    var body: some View {
        Section {
            hero
                .padding(.vertical, StudioSpace.s3)

            if let toggle {
                // Captures values, not the struct: the house pattern for
                // Binding closures under strict concurrency (LiveSwitch).
                Toggle(isOn: Binding(get: { [isOn = toggle.isOn] in isOn }, set: { [set = toggle.set] in set($0) })) {
                    VStack(alignment: .leading, spacing: StudioSpace.s1) {
                        Text(toggle.isOn ? ResourceState.live.title : ResourceState.off.title)
                        Text(toggle.isOn
                             ? String(localized: "Anyone with the address can open it.")
                             : String(localized: "Returns 404. The address stays yours."))
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .disabled(toggle.isBusy)
                .accessibilityLabel(Text("Status"))
                .accessibilityValue(Text(toggle.isOn ? ResourceState.live.title : ResourceState.off.title))
                .accessibilityIdentifier(toggle.identifier ?? "")
                if let error = toggle.error {
                    FormErrorText(message: error)
                }
            }

            rows()

            if isLapsing {
                StudioBanner(
                    lead: String(localized: "This address is in its release window."),
                    message: String(localized: "It may be released to others soon. How addresses are kept: cardsite.com/url-lifecycle."),
                    tone: .warning
                )
            }
        }
        .studioRowBackground()
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s4) {
            statusLine

            VStack(alignment: .leading, spacing: StudioSpace.s2) {
                Text(verbatim: Self.breakable(title))
                    .studioText(.display)
                    .foregroundStyle(Color.studioText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(Text(verbatim: title))
                if let address, !address.isEmpty {
                    Text(verbatim: address)
                        .studioText(.ui)
                        .foregroundStyle(Color.studioText2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let subtitle, !subtitle.isEmpty {
                    Label {
                        Text(verbatim: subtitle)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: "arrow.turn.down.right")
                            .foregroundStyle(Color.studioText3)
                            .accessibilityHidden(true)
                    }
                    .studioText(.ui)
                    .foregroundStyle(Color.studioText2)
                    .accessibilityHint(Text("Where the address leads"))
                }
            }

            if !figures.isEmpty {
                // Side by side; stacked when they don't fit (AX sizes).
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: StudioSpace.s8) { figureViews }
                    VStack(alignment: .leading, spacing: StudioSpace.s3) { figureViews }
                }
                .padding(.top, StudioSpace.s1)
            }

            if url != nil || cardURL != nil || Actions.self != EmptyView.self {
                // The whole row; else Copy Link plus symbols on one line (an
                // iPhone); else stacked (accessibility sizes).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: StudioSpace.s2) { buttons(compact: false) }
                    HStack(spacing: StudioSpace.s2) { buttons(compact: true) }
                    VStack(alignment: .leading, spacing: StudioSpace.s2) { buttons(compact: false) }
                }
                .padding(.top, StudioSpace.s1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusLine: some View {
        if state != nil || kindLabel != nil || didJustSave {
            HStack(spacing: StudioSpace.s2) {
                if let state {
                    state.pill
                }
                if let kindLabel {
                    // A type name ("vCard"), never a sentence: the uppercase
                    // label style is right here.
                    Text(kindLabel)
                        .studioText(.label)
                        .foregroundStyle(Color.studioText3)
                }
                if didJustSave {
                    StudioStatusPill(String(localized: "Saved"), tone: .success)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : StudioAnimation.base, value: didJustSave)
        }
    }

    // MARK: Actions

    @ViewBuilder
    private func buttons(compact: Bool) -> some View {
        if let url {
            Button {
                copy(url)
            } label: {
                Label(copied ? String(localized: "Copied") : ResourceVerb.copyLink.title,
                      systemImage: copied ? "checkmark" : ResourceVerb.copyLink.systemImage)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(HeroActionStyle(prominent: true))
            .fixedSize()
        }
        Group {
            if let url {
                Button {
                    openURL(url)
                } label: {
                    Label(String(localized: "Open"), systemImage: ResourceVerb.openInBrowser.systemImage)
                }
                .accessibilityLabel(Text(ResourceVerb.openInBrowser.title))
            }
            if let cardURL {
                Button {
                    openURL(cardURL)
                } label: {
                    Label(String(localized: "Card"), systemImage: ResourceVerb.showCard.systemImage)
                }
                .accessibilityLabel(Text(ResourceVerb.showCard.title))
                .accessibilityHint(cardHint.map { Text($0) } ?? Text(""))
            }
            actions()
        }
        .buttonStyle(HeroActionStyle())
        .labelStyle(compact ? AnyLabelStyle.iconOnly : AnyLabelStyle.titleAndIcon)
        .fixedSize()
    }

    /// Lets an address wrap after a dot or slash ("links.example.com/
    /// launch") instead of inside a word.
    static func breakable(_ address: String) -> String {
        address
            .replacingOccurrences(of: ".", with: ".\u{200B}")
            .replacingOccurrences(of: "/", with: "/\u{200B}")
    }

    @ViewBuilder
    private var figureViews: some View {
        ForEach(figures) { figure in
            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text(verbatim: figure.value?.figure ?? "—")
                    .studioText(.title)
                    .foregroundStyle(Color.studioText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(figure.title)
                    .studioText(.label)
                    .foregroundStyle(Color.studioText3)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(figure.title))
            .accessibilityValue(Text(verbatim: figure.value?.grouped ?? String(localized: "Not known yet")))
        }
    }

    private func copy(_ url: URL) {
        Pasteboard.copy(url.absoluteString)
        Haptics.success()
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

/// `labelStyle` needs one concrete type for both branches.
private struct AnyLabelStyle: LabelStyle {
    let iconOnlyStyle: Bool

    static let iconOnly = AnyLabelStyle(iconOnlyStyle: true)
    static let titleAndIcon = AnyLabelStyle(iconOnlyStyle: false)

    func makeBody(configuration: Configuration) -> some View {
        if iconOnlyStyle {
            Label(configuration)
                .labelStyle(.iconOnly)
        } else {
            Label(configuration)
                .labelStyle(.titleAndIcon)
        }
    }
}

/// The header's Live switch: its state, whether a change is in flight, the
/// last failure, and what turning it on or off does.
struct ResourceLiveToggle {
    let isOn: Bool
    var isBusy = false
    var error: String? = nil
    /// For UI tests ("link.detail.enabled").
    var identifier: String? = nil
    let set: @MainActor (Bool) -> Void
}

/// A display figure in the header: the number ("—" while unknown),
/// printed with `Int.figure`, over its label.
struct ResourceFigure: Identifiable {
    let title: String
    let value: Int?
    var id: String { title }
}

extension ResourceHeaderSection where Rows == EmptyView {
    init(state: ResourceState?, kindLabel: String? = nil, didJustSave: Bool = false, title: String,
         address: String? = nil, subtitle: String? = nil, url: URL? = nil, cardURL: URL? = nil,
         cardHint: String? = nil, toggle: ResourceLiveToggle? = nil, figures: [ResourceFigure] = [], isLapsing: Bool = false,
         @ViewBuilder actions: @escaping () -> Actions) {
        self.init(state: state, kindLabel: kindLabel, didJustSave: didJustSave, title: title, address: address,
                  subtitle: subtitle, url: url, cardURL: cardURL, cardHint: cardHint, toggle: toggle,
                  figures: figures, isLapsing: isLapsing, actions: actions, rows: { EmptyView() })
    }
}

#Preview("Resource header") {
    Form {
        ResourceHeaderSection(
            state: .live,
            didJustSave: true,
            title: "card.site/spring-menu",
            subtitle: "example.com/menu",
            url: URL(string: "https://card.site/spring-menu"),
            cardURL: URL(string: "https://card.site/@spring-menu"),
            toggle: .init(isOn: true, set: { _ in }),
            figures: [
                .init(title: "Clicks · 30d", value: 412),
                .init(title: "Visitors · 30d", value: 288),
                .init(title: "All time", value: 128_400),
            ]
        ) {
            EmptyView()
        } rows: {
            Button {} label: { ResourceVerb.statistics.label }
        }
    }
    .studioForm()
}

#Preview("Resource header, AX3") {
    Form {
        ResourceHeaderSection(
            state: .off,
            kindLabel: "vCard",
            title: "Augusta Lovelace",
            address: "card.site/ncv-ada",
            url: URL(string: "https://card.site/ncv-ada"),
            cardURL: URL(string: "https://card.site/@ncv-ada"),
            figures: [.init(title: "All time", value: 128)]
        ) {
            Button {} label: { Label("Add to Contacts", systemImage: "person.crop.circle.badge.plus") }
        }
    }
    .studioForm()
    .environment(\.dynamicTypeSize, .accessibility3)
}

/// The hero's actions: opaque Studio capsules on the content card. Unlike
/// `StudioButtonStyle` it leaves the label style to the caller, so the
/// compact row can drop to symbols. `.borderless` semantics in a `Form`
/// row come with any custom style: each button keeps its own tap.
struct HeroActionStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        HeroActionBody(configuration: configuration, prominent: prominent)
    }
}

private struct HeroActionBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .studioText(.ui)
            .fontWeight(.semibold)
            .padding(.horizontal, StudioSpace.s4)
            .frame(minWidth: StudioLayout.tapTarget, minHeight: StudioLayout.tapTarget)
            .foregroundStyle(prominent ? Color.studioAccentInk : Color.studioText)
            .background(prominent ? Color.studioAccent : Color.studioSurface2, in: Capsule())
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : Color.studioBorder, lineWidth: 0.5))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(reduceMotion ? nil : StudioAnimation.spring, value: configuration.isPressed)
    }
}
