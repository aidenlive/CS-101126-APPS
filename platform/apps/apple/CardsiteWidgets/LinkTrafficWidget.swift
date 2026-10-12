import SwiftUI
import WidgetKit
import AppIntents
import StudioKit
import CardsiteKit

// MARK: - Configuration

/// Edit Widget → Link. Left empty, the small widget follows the most-clicked
/// link; the medium widget pins the chosen link first, then the top links.
struct LinkTrafficConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Link Traffic" }
    static var description: IntentDescription? {
        IntentDescription("Clicks on your short links over the last 7 days.")
    }

    @Parameter(title: "Link")
    var link: LinkEntity?

    init() {}
}

// MARK: - Timeline

struct LinkTraffic: Identifiable, Hashable, Sendable {
    let id: Int
    /// `card.site/slug`.
    let address: String
    /// All-time clicks.
    let clicks: Int
    /// The last 7 UTC days, oldest first. Empty when it couldn't be loaded.
    let week: [Int]

    var weekTotal: Int { week.reduce(0, +) }
}

struct LinkTrafficEntry: TimelineEntry {
    enum State: Hashable, Sendable {
        case links([LinkTraffic])
        /// Signed in, but no short links yet.
        case empty
        case signedOut
        case failed(String)
    }

    let date: Date
    let state: State

    static let sample = LinkTrafficEntry(date: .now, state: .links([
        LinkTraffic(id: 1, address: "card.site/spring-menu", clicks: 12_480, week: [140, 162, 155, 210, 198, 260, 241]),
        LinkTraffic(id: 2, address: "card.site/launch", clicks: 4_310, week: [40, 52, 61, 48, 70, 66, 81]),
        LinkTraffic(id: 3, address: "card.site/careers", clicks: 980, week: [9, 14, 12, 8, 17, 15, 20]),
    ]))
}

struct LinkTrafficProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LinkTrafficEntry {
        .sample
    }

    func snapshot(for configuration: LinkTrafficConfiguration, in context: Context) async -> LinkTrafficEntry {
        if context.isPreview { return .sample }
        return LinkTrafficEntry(date: .now, state: await load(configuration, family: context.family))
    }

    func timeline(for configuration: LinkTrafficConfiguration, in context: Context) async -> Timeline<LinkTrafficEntry> {
        let state = await load(configuration, family: context.family)
        // `/statistics` is cached for 5 minutes on the server; half an hour
        // keeps within the widget refresh budget. Failures retry sooner.
        let minutes: Double
        switch state {
        case .failed: minutes = 15
        case .signedOut: minutes = 60
        case .links, .empty: minutes = 30
        }
        return Timeline(entries: [LinkTrafficEntry(date: .now, state: state)],
                        policy: .after(Date.now.addingTimeInterval(minutes * 60)))
    }

    private func load(_ configuration: LinkTrafficConfiguration, family: WidgetFamily) async -> LinkTrafficEntry.State {
        let session: IntentSession
        do {
            session = try await IntentSession.open()
        } catch {
            return .signedOut
        }
        let client = session.client
        let addresses = session.addresses
        do {
            let page = try await client.links(page: 1, search: nil)
            var links = page.items
                .filter { $0.type == LinkKind.shortLink }
                .sorted { $0.clicks > $1.clicks }
            if let pinnedID = configuration.link?.id {
                links.removeAll { $0.id == pinnedID }
                do {
                    let pinned = try await client.link(id: pinnedID)
                    links.insert(pinned, at: 0)
                } catch APIError.invalid {
                    // The chosen link was deleted: fall back to the top links.
                }
            }
            let shown = Array(links.prefix(family == .systemSmall ? 1 : 3))
            guard !shown.isEmpty else { return .empty }

            let weeks = await withTaskGroup(of: (Int, [Int]).self) { group in
                for link in shown {
                    group.addTask {
                        // A missing sparkline isn't worth failing the widget.
                        (link.id, (try? await WeekTraffic.load(linkID: link.id, client: client)) ?? [])
                    }
                }
                var result: [Int: [Int]] = [:]
                for await (id, week) in group { result[id] = week }
                return result
            }
            return .links(shown.map {
                LinkTraffic(id: $0.id, address: addresses.display(for: $0.slug), clicks: $0.clicks,
                            week: weeks[$0.id] ?? [])
            })
        } catch APIError.sessionExpired {
            return .signedOut
        } catch {
            return .failed(widgetFailureMessage(error))
        }
    }
}

// MARK: - Widget

struct LinkTrafficWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: CardsiteWidgetKind.linkTraffic,
                               intent: LinkTrafficConfiguration.self,
                               provider: LinkTrafficProvider()) { entry in
            LinkTrafficWidgetView(entry: entry)
        }
        .configurationDisplayName("Link traffic")
        .description("Clicks on your short links over the last 7 days.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LinkTrafficWidgetView: View {
    let entry: LinkTrafficEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                Color.studioSurface
            }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.state {
        case .links(let links):
            if family == .systemSmall, let link = links.first {
                LinkTrafficSmall(link: link)
                    .widgetURL(CardsiteDeepLink.link(id: link.id).url)
            } else {
                LinkTrafficMedium(links: links)
                    .widgetURL(CardsiteDeepLink.home.url)
            }
        case .empty:
            WidgetMessageView(systemImage: "link.badge.plus",
                              title: String(localized: "No short links yet"),
                              message: String(localized: "Create one in Cardsite to see its clicks here."))
                .widgetURL(CardsiteDeepLink.home.url)
        case .signedOut:
            WidgetMessageView.signedOut(String(localized: "Open Cardsite to see your links' clicks here."))
                .widgetURL(CardsiteDeepLink.home.url)
        case .failed(let message):
            WidgetMessageView.failed(message)
                .widgetURL(CardsiteDeepLink.home.url)
        }
    }
}

/// One link: its address, all-time clicks and the week's line.
private struct LinkTrafficSmall: View {
    let link: LinkTraffic

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s1) {
            Text(verbatim: link.address)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText2)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(alignment: .firstTextBaseline, spacing: StudioSpace.s1) {
                Text(verbatim: link.clicks.clickFigure)
                    .studioText(.title)
                    .foregroundStyle(Color.studioText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .widgetAccentable()
                Text(link.clicks == 1 ? LocalizedStringKey("click") : LocalizedStringKey("clicks"))
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
            }
            .accessibilityElement(children: .combine)
            if link.week.isEmpty {
                Spacer(minLength: 0)
            } else {
                Sparkline(values: link.week)
                    .frame(maxHeight: .infinity)
                Text("7 days · \(link.weekTotal.clickFigure)")
                    .studioText(.meta)
                    .foregroundStyle(Color.studioText3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The top three: glyph, address and the week's total, a sparkline, and
/// all-time clicks trailing. Each row opens its link.
private struct LinkTrafficMedium: View {
    let links: [LinkTraffic]

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s2) {
            HStack {
                StudioKicker(String(localized: "Top links"))
                Spacer(minLength: StudioSpace.s2)
                Text("Clicks")
                    .studioText(.meta)
                    .foregroundStyle(Color.studioText3)
            }
            ForEach(links) { link in
                Link(destination: CardsiteDeepLink.link(id: link.id).url) {
                    LinkTrafficRow(link: link)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct LinkTrafficRow: View {
    let link: LinkTraffic

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        HStack(spacing: StudioSpace.s3) {
            Image(systemName: "link")
                .imageScale(.small)
                .foregroundStyle(Color.studioAccentLine)
                .padding(StudioSpace.s1)
                .background {
                    if renderingMode == .fullColor {
                        RoundedRectangle(cornerRadius: StudioRadius.xs, style: .continuous)
                            .fill(Color.studioSurface2)
                    }
                }
                .widgetAccentable()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: link.address)
                    .studioText(.ui)
                    .foregroundStyle(Color.studioText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !link.week.isEmpty {
                    Text("\(link.weekTotal.clickFigure) · 7 days")
                        .studioText(.meta)
                        .foregroundStyle(Color.studioText3)
                }
            }
            Spacer(minLength: StudioSpace.s2)
            if !link.week.isEmpty {
                Sparkline(values: link.week)
                    .frame(width: StudioSpace.s16)
                    .accessibilityHidden(true)
            }
            Text(verbatim: link.clicks.clickFigure)
                .studioText(.ui)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(Color.studioText)
                .widgetAccentable()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    LinkTrafficWidget()
} timeline: {
    LinkTrafficEntry.sample
    LinkTrafficEntry(date: .now, state: .signedOut)
}

#Preview("Medium", as: .systemMedium) {
    LinkTrafficWidget()
} timeline: {
    LinkTrafficEntry.sample
    LinkTrafficEntry(date: .now, state: .empty)
    LinkTrafficEntry(date: .now, state: .failed("You're offline. This updates when you're back."))
}
