import SwiftUI
import StudioKit

/// The head of a saved resource's detail form, shared by the short link
/// detail and every resource editor: the state pill (and "Saved"), the
/// name, the address, Copy Link / Open in Browser / Show Card plus the
/// type's own actions, the Live switch, the figures, then the caller's rows
/// (Statistics, Create QR Code) and the release-window banner.
///
///     ResourceHeaderSection(
///         state: ResourceState(isEnabled: link.isEnabled, isLapsing: link.isLapsing),
///         title: "card.site/spring-menu", url: url, cardURL: card,
///         toggle: .init(isOn: link.isEnabled, isBusy: busy, set: { … }),
///         figures: [.init(title: String(localized: "Clicks · all time"), value: 1_284)]
///     ) {
///         // extra StudioButtons, next to Copy Link
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
    var address: String? = nil
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
    @Environment(\.toasts) private var toasts
    @State private var copied = false

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: StudioSpace.s3) {
                HStack(spacing: StudioSpace.s2) {
                    if let state {
                        state.pill
                    }
                    if let kindLabel {
                        Text(kindLabel)
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText3)
                    }
                    if didJustSave {
                        StudioStatusPill(String(localized: "Saved"), tone: .success)
                            .transition(.opacity)
                    }
                }
                Text(verbatim: Self.breakable(title))
                    .studioText(.title)
                    .foregroundStyle(Color.studioText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let address {
                    Text(verbatim: address)
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                // Full row; else Copy Link plus icon buttons on one line (an
                // iPhone width); else stacked (accessibility sizes).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: StudioSpace.s2) { buttons }
                    HStack(spacing: StudioSpace.s2) { compactButtons }
                    VStack(alignment: .leading, spacing: StudioSpace.s2) { buttons }
                }
                .padding(.top, StudioSpace.s1)
            }
            .padding(.vertical, StudioSpace.s2)

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

            if !figures.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: StudioSpace.s6) { figureViews }
                    VStack(alignment: .leading, spacing: StudioSpace.s3) { figureViews }
                }
                .padding(.vertical, StudioSpace.s1)
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

    @ViewBuilder
    private var buttons: some View {
        if let url {
            StudioButton(copied ? String(localized: "Copied") : ResourceVerb.copyLink.title,
                         systemImage: copied ? "checkmark" : ResourceVerb.copyLink.systemImage,
                         variant: .primary) {
                copy(url)
            }
            StudioButton(ResourceVerb.openInBrowser.title, systemImage: ResourceVerb.openInBrowser.systemImage,
                         variant: .outline) {
                openURL(url)
            }
        }
        if let cardURL {
            StudioButton(ResourceVerb.showCard.title, systemImage: ResourceVerb.showCard.systemImage,
                         variant: .ghost) {
                openURL(cardURL)
            }
            .accessibilityHint(cardHint.map { Text($0) } ?? Text(""))
        }
        actions()
    }

    @ViewBuilder
    private var compactButtons: some View {
        if let url {
            StudioButton(copied ? String(localized: "Copied") : ResourceVerb.copyLink.title,
                         systemImage: copied ? "checkmark" : ResourceVerb.copyLink.systemImage,
                         variant: .primary) {
                copy(url)
            }
            StudioIconButton(systemImage: ResourceVerb.openInBrowser.systemImage,
                             label: ResourceVerb.openInBrowser.title) {
                openURL(url)
            }
        }
        if let cardURL {
            StudioIconButton(systemImage: ResourceVerb.showCard.systemImage,
                             label: ResourceVerb.showCard.title) {
                openURL(cardURL)
            }
            .accessibilityHint(cardHint.map { Text($0) } ?? Text(""))
        }
        actions()
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
                Text(figure.title)
                    .studioText(.label)
                    .foregroundStyle(Color.studioText3)
                Text(verbatim: figure.value?.figure ?? "—")
                    .studioText(.titleSm)
                    .foregroundStyle(Color.studioText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
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

/// A display figure in the header: a label over the number ("—" while
/// unknown), printed with `Int.figure`.
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
            subtitle: "https://example.com/menu",
            url: URL(string: "https://card.site/spring-menu"),
            cardURL: URL(string: "https://card.site/@spring-menu"),
            toggle: .init(isOn: true, set: { _ in }),
            figures: [
                .init(title: "Clicks · 30d", value: 412),
                .init(title: "Visitors · 30d", value: 288),
                .init(title: "Clicks · all time", value: 128_400),
            ]
        ) {
            EmptyView()
        } rows: {
            Button {} label: { ResourceVerb.statistics.label }
        }
    }
    .studioForm()
}
