import SwiftUI
import Charts
import StudioKit
import CardsiteKit

// The four parts of Home, top to bottom, each a Studio composition:
// greeting (page head + headline figures), create, statistics, recents.

// MARK: - Greeting

/// The page head: date kicker, a two-line greeting with the first name as
/// the serif accent, the lead, and the three headline figures.
struct HomeGreeting: View {
    @Environment(AppModel.self) private var app
    let summary: DashboardSummary?

    var body: some View {
        StudioPageHead(
            kicker: kicker,
            title: greeting + "\n",
            accent: firstName + ".",
            description: String(localized: "Your resources are humming. Pick up where you left off, or start something new below.")
        ) {
            HeadlineFigures(summary: summary)
        }
    }

    private var kicker: String {
        let now = Date()
        let weekday = now.formatted(.dateTime.weekday(.wide))
        let date = now.formatted(.dateTime.month(.abbreviated).day())
        return "Cardsite · \(weekday) · \(date)"
    }

    /// Four whole greetings, as the web keeps them, rather than "Good " plus
    /// a word: the time of day doesn't slot into every language the same way.
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case ..<12: return String(localized: "Good morning,")
        case ..<17: return String(localized: "Good afternoon,")
        case ..<21: return String(localized: "Good evening,")
        default: return String(localized: "Good night,")
        }
    }

    private var firstName: String {
        let name = app.user?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return name.split(separator: " ").first.map(String.init) ?? String(localized: "there")
    }
}

/// Total clicks · resources · short links, in display type.
private struct HeadlineFigures: View {
    let summary: DashboardSummary?
    @Environment(\.studioViewport) private var viewport

    private struct Figure: Identifiable {
        let value: Int?
        let label: String
        var id: String { label }
    }

    private var figures: [Figure] {
        [
            Figure(value: summary?.totalClicks, label: String(localized: "Total clicks")),
            Figure(value: summary?.resources, label: String(localized: "Resources")),
            Figure(value: summary?.links, label: String(localized: "Short links")),
        ]
    }

    var body: some View {
        Group {
            if viewport == .compact {
                // Side by side under the greeting; stacked when the text is
                // too large for three across.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: StudioSpace.s6) {
                        ForEach(figures) { figure in
                            column(figure.value, figure.label)
                        }
                    }
                    rows
                }
            } else {
                rows
            }
        }
        .redacted(reason: summary == nil ? .placeholder : [])
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s2) {
            ForEach(figures) { figure in
                HStack(alignment: .firstTextBaseline, spacing: StudioSpace.s3) {
                    number(figure.value)
                    Text(figure.label)
                        .studioText(.label)
                        .foregroundStyle(Color.studioText3)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func column(_ value: Int?, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: StudioSpace.s1) {
            number(value)
            Text(label)
                .studioText(.label)
                .foregroundStyle(Color.studioText3)
        }
        .accessibilityElement(children: .combine)
    }

    private func number(_ value: Int?) -> some View {
        Text(value?.figure ?? "—")
            .monospacedDigit()
            .studioText(.title)
            .foregroundStyle(Color.studioText)
    }
}

// MARK: - Create

/// "Start something new": the paste-a-URL card and a tile per type the app
/// can create.
struct HomeCreateSection: View {
    let columns: Int

    private var tiles: [CreateAction] {
        // The short link has the paste card; every other type gets a tile.
        CreateAction.allCases.filter { $0 != .shortLink }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s5) {
            PageSectionHead(kicker: String(localized: "Create"),
                            title: String(localized: "Start something "),
                            accent: String(localized: "new."))

            if columns >= 2, !tiles.isEmpty {
                Grid(horizontalSpacing: StudioSpace.s4, verticalSpacing: StudioSpace.s4) {
                    GridRow(alignment: .top) {
                        HomePasteCard()
                            .gridCellColumns(columns - 1)
                        tileStack
                    }
                }
            } else {
                VStack(spacing: StudioSpace.s4) {
                    HomePasteCard()
                    tileStack
                }
            }
        }
    }

    private var tileStack: some View {
        VStack(spacing: StudioSpace.s4) {
            ForEach(tiles) { action in
                HomeCreateTile(action: action)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Paste a long URL, get a short one: opens the link editor prefilled.
struct HomePasteCard: View {
    @Environment(AppModel.self) private var app
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: StudioSpace.s5) {
                VStack(alignment: .leading, spacing: StudioSpace.s3) {
                    StudioKicker(String(localized: "Short link · the fast path"))
                    StudioTwoToneTitle(String(localized: "Paste a long URL, get a "),
                                       accent: String(localized: "short one."),
                                       style: .title)
                        .foregroundStyle(Color.studioText)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: StudioSpace.s3) {
                        field
                        shorten
                    }
                    VStack(alignment: .leading, spacing: StudioSpace.s3) {
                        field
                        shorten
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var field: some View {
        HStack(spacing: StudioSpace.s3) {
            Image(systemName: "link")
                .foregroundStyle(Color.studioText3)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: Text(verbatim: "https://example.com/very/long/destination")) {
                Text("URL to shorten")
            }
            .textFieldStyle(.plain)
            .studioText(.ui)
            .focused($isFocused)
            .plainEntry()
            #if os(iOS)
            .keyboardType(.URL)
            .textContentType(.URL)
            #endif
            .submitLabel(.go)
            .onSubmit(compose)
        }
        .padding(.horizontal, StudioSpace.s4)
        .padding(.vertical, StudioSpace.s3)
        .frame(maxWidth: .infinity)
        .background(isFocused ? Color.studioSurface : Color.studioSurface2, in: Capsule())
        .overlay(
            Capsule().strokeBorder(isFocused ? Color.studioAccentLine : Color.studioBorder,
                                   lineWidth: isFocused ? 1 : 0.5)
        )
        .animation(StudioAnimation.base, value: isFocused)
    }

    private var shorten: some View {
        StudioButton(String(localized: "Shorten"), systemImage: "arrow.right", variant: .primary, action: compose)
            .accessibilityHint("Opens a new short link with this address as its destination")
    }

    /// Straight to a new short link: the box already knows the type. An
    /// empty box opens the editor empty, as on the web.
    private func compose() {
        app.composer = .link(destination: text)
        text = ""
        isFocused = false
    }
}

/// One type to create: glyph, name, a line about it.
struct HomeCreateTile: View {
    @Environment(AppModel.self) private var app
    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 40
    let action: CreateAction

    var body: some View {
        Button {
            app.composer = action.composer
        } label: {
            StudioCard(hover: true) {
                HStack(alignment: .top, spacing: StudioSpace.s4) {
                    Image(systemName: action.systemImage)
                        .imageScale(.large)
                        .foregroundStyle(Color.studioAccentLine)
                        .frame(width: glyphSize, height: glyphSize)
                        .background(
                            RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous)
                                .fill(Color.studioAccentSoft)
                        )
                    VStack(alignment: .leading, spacing: StudioSpace.s1) {
                        Text(action.kindTitle)
                            .studioText(.ui)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.studioText)
                        Text(action.blurb)
                            .studioText(.uiSm)
                            .foregroundStyle(Color.studioText3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "plus")
                        .imageScale(.small)
                        .foregroundStyle(Color.studioText3)
                }
            }
        }
        .buttonStyle(StudioPressStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(action.title)
        .accessibilityHint(action.blurb)
    }
}

// MARK: - Statistics

/// "All your resources": clicks and visitors with 30-day sparklines, and
/// the top performer.
struct HomeStatsSection: View {
    let snapshot: HomeModel.Snapshot
    let columns: Int

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s5) {
            PageSectionHead(kicker: String(localized: "Statistics · Last 30 days"),
                            title: String(localized: "All your "),
                            accent: String(localized: "resources."))

            Grid(horizontalSpacing: StudioSpace.s4, verticalSpacing: StudioSpace.s4) {
                if columns >= 3 {
                    GridRow {
                        clicks
                        visitors
                        top
                    }
                } else if columns == 2 {
                    GridRow {
                        clicks
                        visitors
                    }
                    GridRow {
                        top.gridCellColumns(2)
                    }
                } else {
                    GridRow { clicks }
                    GridRow { visitors }
                    GridRow { top }
                }
            }
        }
    }

    private var clicks: some View {
        HomeStatCard(
            systemImage: "cursorarrow.click",
            label: String(localized: "Total clicks"),
            value: snapshot.summary.totalClicks.figure,
            detail: String(localized: "All time · \(snapshot.clicksInWindow.figure) in the last 30 days")
        ) {
            sparkline(\.pageviews, tint: .studioAccentLine, fill: .studioAccentSoft)
        }
    }

    private var visitors: some View {
        HomeStatCard(
            systemImage: "person.2",
            label: String(localized: "Visitors a day"),
            value: snapshot.averageDailyVisitors.figure,
            detail: String(localized: "Average unique visitors, last 30 days")
        ) {
            sparkline(\.visitors, tint: .studioText3, fill: .studioSurface3)
        }
    }

    private var top: some View {
        HomeTopPerformerCard(top: snapshot.top)
    }

    @ViewBuilder
    private func sparkline(_ value: KeyPath<DailyTraffic, Int>, tint: Color, fill: Color) -> some View {
        if snapshot.hasTraffic {
            Sparkline(days: snapshot.traffic, value: value, tint: tint, fill: fill)
        } else {
            Text("No traffic yet")
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText4)
        }
    }
}

/// A Studio stat card: label, display figure, detail, then an accessory
/// (a sparkline) pinned to the bottom so cards in a row line up.
struct HomeStatCard<Accessory: View>: View {
    let systemImage: String
    let label: String
    let value: String
    let detail: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: StudioSpace.s3) {
                Label {
                    Text(label)
                } icon: {
                    Image(systemName: systemImage)
                }
                .studioText(.label)
                .foregroundStyle(Color.studioText3)

                Text(value)
                    .monospacedDigit()
                    .studioText(.title)
                    .foregroundStyle(Color.studioText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(detail)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
                accessory()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// The resource with the most clicks; opens it.
struct HomeTopPerformerCard: View {
    @Environment(AppModel.self) private var app
    let top: Resource?

    var body: some View {
        if let top {
            ResourceOpenLink(resource: top) {
                card(top)
            }
        } else {
            card(nil)
        }
    }

    private func card(_ top: Resource?) -> some View {
        HomeStatCard(
            systemImage: "trophy",
            label: String(localized: "Top performer"),
            value: top.map { app.addresses.display(for: $0.slug) } ?? "—",
            detail: top.map { String(localized: "\($0.clicks.figure) clicks · \($0.kindInfo.title)") }
                ?? String(localized: "No traffic yet")
        ) {
            EmptyView()
        }
    }
}

/// A 30-day area sparkline. Decorative: the card it sits in states the
/// figure, so VoiceOver skips the chart.
struct Sparkline: View {
    let days: [DailyTraffic]
    let value: KeyPath<DailyTraffic, Int>
    let tint: Color
    let fill: Color

    var body: some View {
        let peak = max(1, days.map { $0[keyPath: value] }.max() ?? 1)
        Chart(days) { day in
            AreaMark(
                x: .value("Day", day.date),
                y: .value("Count", day[keyPath: value])
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(LinearGradient(colors: [fill, .clear], startPoint: .top, endPoint: .bottom))

            LineMark(
                x: .value("Day", day.date),
                y: .value("Count", day[keyPath: value])
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: 0...peak)
        .frame(height: StudioSpace.s12)
        .accessibilityHidden(true)
    }
}

// MARK: - Recents

/// "Pick up where you left off": the five most recently edited resources
/// of any type, newest first.
struct HomeRecentsSection: View {
    @Environment(AppModel.self) private var app
    let recent: [Resource]

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s5) {
            PageSectionHead(kicker: String(localized: "Recently edited"),
                            title: String(localized: "Pick up where you "),
                            accent: String(localized: "left off."))

            if recent.isEmpty {
                StudioEmptyState(
                    systemImage: "sparkles",
                    title: String(localized: "Nothing here yet"),
                    message: String(localized: "Create your first short link above and it shows up here.")
                ) {
                    StudioButton(String(localized: "New Short Link"), systemImage: "plus", variant: .outline) {
                        app.composer = .link
                    }
                }
            } else {
                StudioCard(flush: true) {
                    VStack(spacing: 0) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, resource in
                            ResourceOpenLink(resource: resource) {
                                HomeRecentRow(resource: resource)
                            }
                            .contextMenu { ResourceActions(resource: resource) }
                            if index < recent.count - 1 {
                                Divider().overlay(Color.studioBorder)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// ROW anatomy: glyph tile · address over a meta line · trailing figure.
struct HomeRecentRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 40
    let resource: Resource

    private var info: ResourceKindInfo { resource.kindInfo }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: StudioSpace.s3))
            : AnyLayout(HStackLayout(spacing: StudioSpace.s4))

        layout {
            Image(systemName: info.systemImage)
                .imageScale(.large)
                .foregroundStyle(info.isComposed ? Color.studioAccentLine : Color.studioText2)
                .frame(width: glyphSize, height: glyphSize)
                .background(
                    RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous)
                        .fill(info.isComposed ? Color.studioAccentSoft : Color.studioSurface3)
                )

            VStack(alignment: .leading, spacing: StudioSpace.s1) {
                Text(verbatim: app.addresses.display(for: resource.slug))
                    .studioText(.ui)
                    .foregroundStyle(Color.studioText)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .truncationMode(.middle)
                HStack(spacing: StudioSpace.s2) {
                    Text(info.title)
                    if let edited = resource.updatedAt ?? resource.createdAt {
                        Text(verbatim: "·").accessibilityHidden(true)
                        Text(edited, format: .relative(presentation: .named))
                    }
                }
                .studioText(.meta)
                .foregroundStyle(Color.studioText3)
            }

            if !typeSize.isAccessibilitySize {
                Spacer(minLength: StudioSpace.s2)
            }

            HStack(alignment: .firstTextBaseline, spacing: StudioSpace.s3) {
                VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: StudioSpace.s1) {
                    Text(resource.clicks.figure)
                        .monospacedDigit()
                        .studioText(.titleSm)
                        .foregroundStyle(Color.studioText)
                    Text("clicks")
                        .studioText(.meta)
                        .foregroundStyle(Color.studioText3)
                }
                Image(systemName: resource.type == LinkKind.shortLink || resource.type == LinkKind.bioPage ? "chevron.right" : "arrow.up.forward")
                    .imageScale(.small)
                    .foregroundStyle(Color.studioText4)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, StudioSpace.s5)
        .padding(.vertical, StudioSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Opening a resource

/// Opens a resource the way the app can today: a short link pushes its
/// detail, a bio page opens in the Pages editor, and any other type opens
/// its public page in the browser.
struct ResourceOpenLink<Label: View>: View {
    @Environment(AppModel.self) private var app
    // Optional so a preview without the shell still renders.
    @Environment(PagesModel.self) private var pages: PagesModel?
    @Environment(ShellRouter.self) private var router: ShellRouter?
    let resource: Resource
    @ViewBuilder var label: () -> Label

    var body: some View {
        if resource.type == LinkKind.shortLink {
            NavigationLink(value: resource) {
                label()
            }
            .buttonStyle(StudioPressStyle(scale: 0.99))
        } else if resource.type == LinkKind.bioPage, let pages, let router {
            Button {
                pages.openRequest = resource.id
                router.open(.pages)
            } label: {
                label()
            }
            .buttonStyle(StudioPressStyle(scale: 0.99))
            .accessibilityHint("Opens the page editor")
        } else if let url = app.addresses.url(for: resource.slug) {
            Link(destination: url) {
                label()
            }
            .buttonStyle(StudioPressStyle(scale: 0.99))
            .accessibilityHint("Opens in your browser")
        } else {
            label()
        }
    }
}

/// Copy, share and open, for a resource's context menu.
struct ResourceActions: View {
    @Environment(AppModel.self) private var app
    let resource: Resource

    var body: some View {
        if let url = app.addresses.url(for: resource.slug) {
            Button {
                Pasteboard.copy(url.absoluteString)
                Haptics.success()
            } label: {
                Label("Copy Address", systemImage: "doc.on.doc")
            }
            ShareLink(item: url) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Link(destination: url) {
                Label("Open in Browser", systemImage: "safari")
            }
        }
    }
}
