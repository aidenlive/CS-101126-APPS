import SwiftUI
import Charts
import StudioKit
import CardsiteKit

// The four parts of Home, top to bottom (Studio 1.10's editorial home,
// TodayView): the greeting is the ONE focal element; create, the numbers
// and recents sit under quiet section headers, and the numbers are a dense
// rail rather than display-size cards competing with the greeting.

// MARK: - Greeting

/// The page head and the page's only focal element: date kicker, a
/// two-line greeting with the first name as the serif accent, and the lead.
/// The headline figures live in the numbers rail further down.
struct HomeGreeting: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        StudioPageHead(
            kicker: kicker,
            title: greeting + "\n",
            accent: firstName + ".",
            description: String(localized: "Your resources are humming. Pick up where you left off, or start something new below.")
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var kicker: String {
        let now = Date()
        let weekday = now.formatted(.dateTime.weekday(.wide))
        let date = now.formatted(.dateTime.month(.abbreviated).day())
        return String(localized: "Cardsite · \(weekday) · \(date)")
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

// MARK: - Create

/// Create: the paste-a-URL card and a tile per type the app can create.
/// On iPhone the tiles are a snapping shelf under the paste card, so the
/// section reads as one deliberate move rather than a tall stack; at
/// accessibility sizes they stack again.
struct HomeCreateSection: View {
    let columns: Int
    @Environment(\.dynamicTypeSize) private var typeSize

    private var tiles: [CreateAction] {
        // The most-used types only; the `+` menu and the palette list
        // them all. The short link has the paste card instead of a tile.
        CreateAction.featured.filter { $0 != .shortLink }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s4) {
            PageSectionHead(String(localized: "Create"),
                            note: String(localized: "Shorten a link in one move, or start any type."))

            if columns >= 2, !tiles.isEmpty {
                Grid(horizontalSpacing: StudioSpace.s4, verticalSpacing: StudioSpace.s4) {
                    GridRow(alignment: .top) {
                        HomePasteCard()
                            .gridCellColumns(columns - 1)
                        tileStack
                    }
                }
            } else if typeSize.isAccessibilitySize {
                VStack(spacing: StudioSpace.s4) {
                    HomePasteCard()
                    tileStack
                }
            } else {
                VStack(alignment: .leading, spacing: StudioSpace.s4) {
                    HomePasteCard()
                    SnapShelf {
                        ForEach(tiles) { action in
                            HomeCreateTile(action: action, fillsHeight: true)
                                .containerRelativeFrame(.horizontal, count: 4, span: 3, spacing: StudioSpace.s3)
                        }
                    }
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
/// Its Shorten button is the page's one accent (primary) action; the card's
/// own line is plain UI type, not a second display title.
struct HomePasteCard: View {
    @Environment(AppModel.self) private var app
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: StudioSpace.s4) {
                Text("Paste a long URL, get a short one.")
                    .studioText(.ui)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.studioText)
                    .fixedSize(horizontal: false, vertical: true)

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
            #if os(iOS) || os(visionOS)
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

/// One type to create: the neutral catalogue tile (surface, secondary ink,
/// never the accent), name, a line about it.
struct HomeCreateTile: View {
    @Environment(AppModel.self) private var app
    @ScaledMetric(relativeTo: .body) private var glyphSide: CGFloat = StudioLayout.tapTarget
    let action: CreateAction
    /// In a shelf, every tile is as tall as the tallest.
    var fillsHeight = false

    var body: some View {
        Button {
            app.composer = action.composer
        } label: {
            StudioCard(hover: true) {
                HStack(alignment: .top, spacing: StudioSpace.s4) {
                    Image(systemName: action.systemImage)
                        .imageScale(.large)
                        .foregroundStyle(Color.studioText2)
                        .frame(width: glyphSide, height: glyphSide)
                        .background(
                            RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
                                .fill(Color.studioSurface3)
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
                .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
            }
        }
        .buttonStyle(StudioPressStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(action.title)
        .accessibilityHint(action.blurb)
    }
}

// MARK: - Numbers

/// "At a glance": the workspace's figures demoted to one dense rail
/// (Studio's `focal.dense`) — label · value · change per row, hairline
/// dividers, one flush card — so they inform without competing with the
/// greeting. The 30-day sparklines stay as secondary detail on the two
/// traffic rows: inline on wide pages, under the row on iPhone.
struct HomeStatsSection: View {
    let snapshot: HomeModel.Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s4) {
            PageSectionHead(String(localized: "At a glance"),
                            note: String(localized: "Traffic over the last 30 days, and the workspace in numbers."))

            StudioCard(flush: true) {
                VStack(spacing: 0) {
                    clicks
                    HomeRailDivider()
                    visitors
                    HomeRailDivider()
                    HomeRailRow(label: String(localized: "Total clicks"),
                                value: Text(snapshot.summary.totalClicks.figure),
                                detail: String(localized: "All time"))
                    HomeRailDivider()
                    HomeRailRow(label: String(localized: "Resources"),
                                value: Text(snapshot.summary.resources.figure))
                    HomeRailDivider()
                    HomeRailRow(label: String(localized: "Short links"),
                                value: Text(snapshot.summary.links.figure))
                    HomeRailDivider()
                    HomeTopPerformerRow(top: snapshot.top)
                }
            }
        }
    }

    private var clicks: some View {
        let trend = Self.trend(snapshot.traffic, \.pageviews)
        return HomeRailRow(
            label: String(localized: "Clicks · 30 days"),
            value: Text(snapshot.clicksInWindow.figure),
            change: snapshot.hasTraffic ? trend : nil,
            sparkline: sparkline(\.pageviews, tint: .studioViz1)
        )
    }

    private var visitors: some View {
        let trend = Self.trend(snapshot.traffic, \.visitors)
        return HomeRailRow(
            label: String(localized: "Visitors a day"),
            value: Text(snapshot.averageDailyVisitors.figure),
            change: snapshot.hasTraffic ? trend : nil,
            sparkline: sparkline(\.visitors, tint: .studioViz2)
        )
    }

    /// The chart palette, as the Statistics chart draws the same series
    /// (clicks `studioViz1`, visitors `studioViz2`). None before traffic.
    private func sparkline(_ value: KeyPath<DailyTraffic, Int>, tint: Color) -> Sparkline? {
        guard snapshot.hasTraffic else { return nil }
        // No spoken trend here: the row's change column already reads it.
        return Sparkline(days: snapshot.traffic, value: value, tint: tint, fill: tint.opacity(0.22))
    }

    /// The rail's change column: a short figure ("+12%") for the `.meta`
    /// style, which is uppercase and so never carries a sentence, plus the
    /// sentence for VoiceOver.
    static func trend(_ days: [DailyTraffic], _ value: KeyPath<DailyTraffic, Int>) -> HomeTrend {
        let spoken = trendSummary(days, value)
        let half = days.count / 2
        guard half > 0 else { return HomeTrend(short: "—", spoken: spoken, direction: .level) }
        let previous = days.prefix(half).reduce(0) { $0 + $1[keyPath: value] }
        let recent = days.suffix(half).reduce(0) { $0 + $1[keyPath: value] }
        guard previous > 0 else {
            return recent > 0
                ? HomeTrend(short: String(localized: "New"), spoken: spoken, direction: .up)
                : HomeTrend(short: "—", spoken: spoken, direction: .level)
        }
        let change = Double(recent - previous) / Double(previous)
        let percent = abs(change).formatted(.percent.precision(.fractionLength(0)))
        if change >= 0.005 {
            return HomeTrend(short: "+\(percent)", spoken: spoken, direction: .up)
        } else if change <= -0.005 {
            return HomeTrend(short: "−\(percent)", spoken: spoken, direction: .down)
        }
        return HomeTrend(short: String(localized: "Level"), spoken: spoken, direction: .level)
    }

    /// "Up 12% on the previous 15 days": the sparkline's shape in words, so
    /// the trend isn't visual-only.
    static func trendSummary(_ days: [DailyTraffic], _ value: KeyPath<DailyTraffic, Int>) -> String {
        let half = days.count / 2
        guard half > 0 else { return String(localized: "Not enough days to compare") }
        let previous = days.prefix(half).reduce(0) { $0 + $1[keyPath: value] }
        let recent = days.suffix(half).reduce(0) { $0 + $1[keyPath: value] }
        guard previous > 0 else {
            return recent > 0
                ? String(localized: "Up from none in the previous \(half) days")
                : String(localized: "No traffic in the last \(half * 2) days")
        }
        let change = Double(recent - previous) / Double(previous)
        let percent = abs(change).formatted(.percent.precision(.fractionLength(0)))
        if change >= 0.005 {
            return String(localized: "Up \(percent) on the previous \(half) days")
        } else if change <= -0.005 {
            return String(localized: "Down \(percent) on the previous \(half) days")
        }
        return String(localized: "Level with the previous \(half) days")
    }
}

/// A trend for the rail's change column.
struct HomeTrend {
    enum Direction { case up, down, level }

    /// A figure, never a sentence: the column is the uppercase `.meta` style.
    let short: String
    /// The sentence VoiceOver reads instead.
    let spoken: String
    let direction: Direction

    var tint: Color {
        switch direction {
        case .up: return .studioSuccess
        case .down: return .studioWarning
        case .level: return .studioText3
        }
    }
}

/// The rail's hairline (Studio's 0.5pt border), between rows.
struct HomeRailDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.studioBorder)
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

/// One line of the numbers rail: `.label` in tertiary ink, the value in
/// `.ui`, the change in `.meta`. A sparkline, when there is one, sits
/// between label and value on wide pages and under the line on iPhone; at
/// accessibility sizes the line stacks so nothing truncates.
struct HomeRailRow: View {
    let label: String
    let value: Text
    var change: HomeTrend? = nil
    /// A sentence-case note under the value (`.uiSm`), for context the
    /// uppercase change column can't carry.
    var detail: String? = nil
    var sparkline: Sparkline? = nil
    /// An address rather than a figure: it loses its middle, not its slug.
    var isAddress = false

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.studioViewport) private var viewport
    /// The change column's width, so values line up down the rail.
    @ScaledMetric(relativeTo: .caption) private var changeWidth: CGFloat = StudioSpace.s16
    @ScaledMetric(relativeTo: .body) private var inlineSparkHeight: CGFloat = StudioSpace.s6
    @ScaledMetric(relativeTo: .body) private var stackedSparkHeight: CGFloat = StudioSpace.s8

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    labelText
                    valueText
                    detailText
                    changeText
                    if let sparkline {
                        sparkline.frame(height: stackedSparkHeight)
                            .padding(.top, StudioSpace.s1)
                    }
                }
            } else if viewport == .compact {
                VStack(alignment: .leading, spacing: StudioSpace.s2) {
                    line(inlineSparkline: false)
                    if let sparkline {
                        sparkline.frame(height: stackedSparkHeight)
                    }
                }
            } else {
                line(inlineSparkline: true)
            }
        }
        .padding(.horizontal, StudioSpace.s4)
        .padding(.vertical, StudioComposition.rhythmDetailRow)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func line(inlineSparkline: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: StudioSpace.s4) {
            labelText
                .layoutPriority(1)
            if inlineSparkline, let sparkline {
                sparkline
                    .frame(maxWidth: .infinity)
                    .frame(height: inlineSparkHeight)
            } else {
                Spacer(minLength: StudioSpace.s4)
            }
            VStack(alignment: .trailing, spacing: 0) {
                valueText
                detailText
            }
            // A fixed column, present on every row, so values line up
            // down the rail whether or not a row has a change.
            changeText
                .frame(width: changeWidth, alignment: .trailing)
        }
    }

    private var labelText: some View {
        Text(label)
            .studioText(.label)
            .foregroundStyle(Color.studioText3)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
    }

    private var valueText: some View {
        value
            .monospacedDigit()
            .studioText(.ui)
            .foregroundStyle(Color.studioText)
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .truncationMode(isAddress ? .middle : .tail)
            .contentTransition(.numericText())
    }

    @ViewBuilder
    private var detailText: some View {
        if let detail {
            Text(detail)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText3)
        }
    }

    /// The change as a short figure; VoiceOver reads the sentence.
    @ViewBuilder
    private var changeText: some View {
        if let change {
            Text(change.short)
                .studioText(.meta)
                .foregroundStyle(change.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel(Text(change.spoken))
        }
    }
}

/// The resource with the most clicks, as the rail's last row; opens it.
struct HomeTopPerformerRow: View {
    @Environment(AppModel.self) private var app
    let top: Resource?

    var body: some View {
        if let top {
            ResourceOpenLink(resource: top) {
                row(top)
            }
        } else {
            row(nil)
        }
    }

    private func row(_ top: Resource?) -> some View {
        HomeRailRow(
            label: String(localized: "Top performer"),
            value: Text(verbatim: top.map { app.addresses.display(for: $0.slug) } ?? "—"),
            detail: top.map { String(localized: "\($0.clicks.figure) clicks · \($0.kindInfo.title)") }
                ?? String(localized: "No traffic yet"),
            isAddress: true
        )
    }
}

/// A 30-day area sparkline. The row it sits in states the figure; the
/// sparkline adds the trend, in words, for VoiceOver. The row sets its
/// height.
struct Sparkline: View {
    let days: [DailyTraffic]
    let value: KeyPath<DailyTraffic, Int>
    let tint: Color
    let fill: Color
    var trend: String = ""

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
        .accessibilityElement()
        .accessibilityLabel(Text("Trend"))
        .accessibilityValue(Text(trend))
        .accessibilityHidden(trend.isEmpty)
    }
}


// MARK: - Recents

/// "Pick up where you left off": the five most recently edited resources
/// of any type, newest first.
struct HomeRecentsSection: View {
    @Environment(AppModel.self) private var app
    let recent: [Resource]
    @State private var statisticsFor: Resource? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s4) {
            PageSectionHead(String(localized: "Recently edited"),
                            note: String(localized: "Pick up where you left off."))

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
                            .contextMenu { ResourceActions(resource: resource) { statisticsFor = resource } }
                            if index < recent.count - 1 {
                                HomeRailDivider()
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $statisticsFor) { resource in
            NavigationStack {
                StatisticsScreen(linkID: resource.id, subtitle: app.addresses.display(for: resource.slug))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { statisticsFor = nil }
                        }
                    }
            }
            .cardsiteSheet(.page)
        }
    }
}

/// A recent resource in the shared row anatomy: address, type and when it
/// was edited, clicks, and where tapping goes (in the app, or the browser).
struct HomeRecentRow: View {
    @Environment(AppModel.self) private var app
    let resource: Resource

    private var info: ResourceKindInfo { resource.kindInfo }

    private var meta: Text {
        guard let edited = resource.updatedAt ?? resource.createdAt else { return Text(info.title) }
        return Text(info.title) + Text(verbatim: " · ") + Text(edited, format: .relative(presentation: .named))
    }

    var body: some View {
        CardsiteResourceRow(
            systemImage: info.systemImage,
            isLive: resource.isEnabled,
            title: Text(verbatim: app.addresses.display(for: resource.slug)),
            subtitle: meta,
            state: ResourceState(isEnabled: resource.isEnabled, isLapsing: resource.isLapsing),
            clicks: resource.clicks
        ) {
            Image(systemName: opensInApp ? "chevron.right" : "arrow.up.forward")
                .imageScale(.small)
                .foregroundStyle(Color.studioText4)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, StudioSpace.s4)
        .padding(.vertical, StudioSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var opensInApp: Bool {
        resource.type == LinkKind.shortLink || resource.type == LinkKind.bioPage
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

/// A recent resource's context menu: the shared vocabulary (copy, open,
/// share, card, statistics).
struct ResourceActions: View {
    @Environment(AppModel.self) private var app
    let resource: Resource
    var statistics: (() -> Void)? = nil

    var body: some View {
        ResourceMenuItems(actions: ResourceActionSet(
            url: app.addresses.url(for: resource.slug),
            cardURL: app.addresses.cardURL(for: resource.slug),
            statistics: statistics
        ))
    }
}
