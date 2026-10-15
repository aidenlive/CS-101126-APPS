import SwiftUI
import StudioKit
import CardsiteKit

/// Where a "Full statistics" button navigates. Push it inside a
/// `NavigationStack` that declares
/// `.navigationDestination(for: StatisticsRoute.self) { StatisticsScreen(route: $0) }`.
struct StatisticsRoute: Hashable {
    /// nil: the whole workspace.
    let linkID: Int?
    /// Shown under the title, e.g. "card.site/spring-menu".
    var subtitle: String?
}

/// Statistics for one resource, or for everything when `linkID` is nil:
/// 7/30/90-day range, four figures, the daily chart and a breakdown by any
/// of the 11 dimensions the server groups by.
///
/// Push it in a navigation stack, or present it in a sheet wrapped in one.
struct StatisticsScreen: View {
    @Environment(AppModel.self) private var app
    @State private var loadedModel: StatisticsModel? = nil

    let linkID: Int?
    var subtitle: String?
    private var suppliedModel: StatisticsModel?

    init(linkID: Int?, subtitle: String? = nil) {
        self.linkID = linkID
        self.subtitle = subtitle
    }

    init(route: StatisticsRoute) {
        self.init(linkID: route.linkID, subtitle: route.subtitle)
    }

    /// Preview seam.
    init(model: StatisticsModel, subtitle: String? = nil) {
        if case .link(let id) = model.target { self.linkID = id } else { self.linkID = nil }
        self.subtitle = subtitle
        self.suppliedModel = model
    }

    private var model: StatisticsModel? { suppliedModel ?? loadedModel }

    var body: some View {
        Group {
            if let model {
                StatisticsContent(model: model, subtitle: subtitle)
            } else {
                // The model exists one frame later (`.task`); an empty page
                // rather than a spinner that flashes.
                Color.studioBg
                    .accessibilityElement()
                    .accessibilityLabel(Text("Loading"))
            }
        }
        .background(Color.studioBg)
        .pageHeadNavigationTitle(linkID == nil
            ? String(localized: "Statistics")
            : String(localized: "Link Statistics"))
        .task {
            if model == nil {
                let model = StatisticsModel(client: app.client, target: StatisticsTarget(linkID: linkID))
                model.onError = app.handle
                loadedModel = model
            }
        }
    }
}

private struct StatisticsContent: View {
    @Bindable var model: StatisticsModel
    let subtitle: String?

    @Environment(\.studioViewport) private var viewport
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var tileMinWidth: CGFloat = 150

    /// iPad and Mac at wide widths: tiles and chart side by side.
    private var isWide: Bool {
        viewport != .compact && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        Group {
            if case .failed(let error) = model.overview {
                ErrorStateView(error: error) { [model] in await model.reload() }
            } else {
                ScrollView {
                    // The dashboard page anatomy Home uses: viewport
                    // padding, the page head, sections a section gap apart.
                    VStack(alignment: .leading, spacing: viewport.sectionGap) {
                        header
                        if let error = model.refreshError {
                            RefreshErrorBanner(error: error) { model.dismissRefreshError() }
                        }
                        if isWide {
                            // A balanced two-column grid: the four tiles as
                            // a 2 × 2 block beside the chart card.
                            HStack(alignment: .top, spacing: StudioSpace.s4) {
                                tiles(columns: [GridItem(.flexible(), spacing: StudioSpace.s3),
                                                GridItem(.flexible(), spacing: StudioSpace.s3)])
                                    .frame(maxWidth: .infinity)
                                trafficCard
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            tiles(columns: [GridItem(.adaptive(minimum: tileMinWidth), spacing: StudioSpace.s3)])
                            trafficCard
                        }
                        breakdownCard
                    }
                    .padding(.horizontal, viewport.contentPadding)
                    .padding(.top, StudioSpace.s6)
                    .padding(.bottom, StudioSpace.s12)
                    .readableWidth(.dashboard)
                }
                .refreshable { [model] in await model.reload() }
            }
        }
        // SwiftUI cancels the previous load on change, so a fast switch
        // between ranges can't land late.
        .task(id: model.range) { [model] in await model.loadOverview() }
        .task(id: BreakdownKey(range: model.range, dimension: model.dimension)) { [model] in
            await model.loadBreakdown()
        }
        .toolbar {
            if model.isRefreshing {
                ToolbarItem(placement: .automatic) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(Text("Updating"))
                }
            }
        }
    }

    private struct BreakdownKey: Hashable {
        let range: StatisticsModel.Range
        let dimension: StatisticsDimension
    }

    // MARK: Header

    /// The dashboard hero: the kicker, the two-tone title, the resource's
    /// address, and the range as one wide segmented pill.
    private var header: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s4) {
            StudioPageHead(
                kicker: String(localized: "Statistics · Last \(model.range.rawValue) days"),
                title: String(localized: "The whole "),
                accent: model.target == .all ? String(localized: "workspace.") : String(localized: "story.")
            )
            if let subtitle {
                Label {
                    Text(verbatim: subtitle)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "link")
                        .foregroundStyle(Color.studioText3)
                }
                .studioText(.ui)
                .foregroundStyle(Color.studioText2)
            }
            rangePicker
        }
    }

    private var rangePicker: some View {
        Picker(String(localized: "Date range"), selection: $model.range) {
            ForEach(StatisticsModel.Range.allCases, id: \.self) { range in
                Text(range.shortTitle)
                    .tag(range)
                    .accessibilityLabel(Text(range.accessibilityTitle))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .frame(maxWidth: viewport == .compact ? .infinity : CardsiteMeasure.narrow.width)
    }

    // MARK: Tiles

    private func tiles(columns: [GridItem]) -> some View {
        let overview = model.overview.value
        let placeholder = overview == nil
        return LazyVGrid(columns: columns, alignment: .leading, spacing: StudioSpace.s3) {
            StatisticTile(
                title: String(localized: "Pageviews"),
                systemImage: "cursorarrow.click",
                value: overview?.pageviews.figure ?? "0000",
                caption: overview.map(Self.rangeCaption) ?? " ",
                isFeatured: true
            )
            StatisticTile(
                title: String(localized: "Visitors"),
                systemImage: "person.2",
                value: overview?.visitors.figure ?? "000",
                caption: overview?.visitorShare.map {
                    String(localized: "\($0.formatted(.percent.precision(.fractionLength(1)))) of pageviews")
                } ?? String(localized: "unique visitors")
            )
            StatisticTile(
                title: String(localized: "Daily average"),
                systemImage: "chart.line.uptrend.xyaxis",
                value: overview.map { $0.isEmpty ? "—" : $0.dailyAverage.figure } ?? "00",
                caption: String(localized: "pageviews per day")
            )
            StatisticTile(
                title: String(localized: "Peak day"),
                systemImage: "calendar",
                value: overview?.peak.map { $0.pageviews.figure } ?? "—",
                caption: overview?.peak.map(Self.dayCaption) ?? String(localized: "no traffic yet")
            )
        }
        .redacted(reason: placeholder ? .placeholder : [])
        .loadingAccessibility(placeholder)
    }

    private static func rangeCaption(_ overview: StatisticsModel.Overview) -> String {
        let format = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return "\(overview.start.formatted(format)) – \(overview.end.formatted(format))"
    }

    private static func dayCaption(_ day: DailyTraffic) -> String {
        day.day?.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) ?? day.date
    }

    // MARK: Traffic

    private var trafficCard: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: StudioSpace.s4) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        StudioKicker(String(localized: "Traffic"))
                        Spacer()
                        TrafficChartLegend()
                    }
                    VStack(alignment: .leading, spacing: StudioSpace.s2) {
                        StudioKicker(String(localized: "Traffic"))
                        TrafficChartLegend()
                    }
                }
                switch model.overview {
                case .idle, .loading:
                    ChartPlaceholder()
                case .failed:
                    EmptyView()
                case .loaded(let overview) where overview.isEmpty:
                    Text("No data for this period")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, StudioSpace.s16)
                case .loaded(let overview):
                    TrafficChart(days: overview.days)
                }
            }
        }
    }

    // MARK: Breakdown

    private var breakdownCard: some View {
        StudioCard {
            VStack(alignment: .leading, spacing: StudioSpace.s4) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center) {
                        StudioKicker(String(localized: "Breakdown"))
                        Spacer()
                        dimensionPicker
                    }
                    VStack(alignment: .leading, spacing: StudioSpace.s2) {
                        StudioKicker(String(localized: "Breakdown"))
                        dimensionPicker
                    }
                }
                switch model.breakdown {
                case .idle, .loading:
                    VStack(spacing: StudioSpace.s2) {
                        ForEach(0..<5, id: \.self) { index in
                            BreakdownBar(label: "Placeholder row", value: 100 - index * 15, share: 0.2,
                                         fraction: 1 - Double(index) * 0.15, isLeading: index == 0)
                        }
                    }
                    .redacted(reason: .placeholder)
                    .loadingAccessibility(true)
                case .failed(let error):
                    InlineErrorState(error: error) { [model] in await model.loadBreakdown() }
                case .loaded(let rows) where rows.isEmpty:
                    Text("No data for this period")
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, StudioSpace.s8)
                case .loaded(let rows):
                    BreakdownList(rows: rows, dimension: model.dimension)
                }
            }
        }
    }

    private var dimensionPicker: some View {
        Picker(selection: Binding(
            get: { model.dimension },
            set: { newValue in
                guard newValue != model.dimension else { return }
                model.dimension = newValue
                model.dimensionChanged()
            }
        )) {
            ForEach(StatisticsDimension.allCases) { dimension in
                Label(dimension.title, systemImage: dimension.systemImage).tag(dimension)
            }
        } label: {
            Text("Breakdown dimension")
        }
        .pickerStyle(.menu)
        .fixedSize()
    }
}

/// One figure: icon and label, the number, and a caption.
struct StatisticTile: View {
    let title: String
    let systemImage: String
    let value: String
    let caption: String
    var isFeatured = false

    var body: some View {
        StudioCard(selected: isFeatured) {
            VStack(alignment: .leading, spacing: StudioSpace.s2) {
                Label(title, systemImage: systemImage)
                    .studioText(.label)
                    .foregroundStyle(Color.studioText3)
                Text(verbatim: value)
                    .studioText(.title)
                    .foregroundStyle(Color.studioText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: caption)
                    .studioText(.uiSm)
                    .foregroundStyle(Color.studioText3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Ranked rows with share of the listed total, the web's `.rank` list.
private struct BreakdownList: View {
    let rows: [StatisticsRow]
    let dimension: StatisticsDimension

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var figureColumn: CGFloat = StudioSpace.s16

    var body: some View {
        let total = rows.reduce(0) { $0 + $1.pageviews }
        let top = rows.map(\.pageviews).max() ?? 0
        VStack(alignment: .leading, spacing: StudioSpace.s2) {
            // The same columns as the bars below: the figures sit under
            // their headings. Bars stack at accessibility sizes, so the
            // heading drops its columns there.
            HStack(spacing: StudioSpace.s3) {
                Text(verbatim: dimension.title)
                Spacer(minLength: StudioSpace.s2)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("Pageviews")
                        .frame(minWidth: figureColumn, alignment: .trailing)
                    Text("Share")
                        .frame(minWidth: figureColumn, alignment: .trailing)
                }
            }
            .padding(.horizontal, StudioSpace.s3)
            .studioText(.meta)
            .foregroundStyle(Color.studioText3)
            .accessibilityHidden(true)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                BreakdownBar(
                    label: dimension.displayLabel(row.label),
                    value: row.pageviews,
                    share: total > 0 ? Double(row.pageviews) / Double(total) : 0,
                    fraction: top > 0 ? Double(row.pageviews) / Double(top) : 0,
                    isLeading: dimension.isRanked && index == 0,
                    figureColumn: figureColumn
                )
            }
        }
    }
}

private struct BreakdownBar: View {
    let label: String
    let value: Int
    let share: Double
    let fraction: Double
    let isLeading: Bool
    /// The figure columns' width, so they line up under the heading.
    var figureColumn: CGFloat = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: StudioSpace.s1) {
                    labelText
                    HStack { valueText; Spacer(); shareText }
                }
            } else {
                HStack(spacing: StudioSpace.s3) {
                    labelText
                    Spacer(minLength: StudioSpace.s2)
                    valueText
                        .frame(minWidth: figureColumn, alignment: .trailing)
                    shareText
                        .frame(minWidth: figureColumn, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, StudioSpace.s3)
        .padding(.vertical, StudioSpace.s2)
        // The share as a quiet fill behind the row, so the label and the
        // figures always sit on a near-surface tint and keep their contrast
        // (a solid lime or grey bar under text failed it). The top row of a
        // ranked list takes the accent: a soft accent fill and an accent rule.
        .background(alignment: .leading) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous)
                        .fill(Color.studioSurface2)
                    RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous)
                        .fill(isLeading ? Color.studioAccentSoft : Color.studioViz1.opacity(0.12))
                        .frame(width: max(StudioSpace.s1, proxy.size.width * fraction))
                }
            }
        }
        .overlay(alignment: .leading) {
            if isLeading {
                Capsule()
                    .fill(Color.studioAccentLine)
                    .frame(width: StudioSpace.s1 / 2)
                    .padding(.vertical, StudioSpace.s2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text("\(value) pageviews, \(share.formatted(.percent.precision(.fractionLength(1))))"))
    }

    private var labelText: some View {
        Text(verbatim: label)
            .fontWeight(isLeading ? .semibold : nil)
            .studioText(.ui)
            .foregroundStyle(Color.studioText)
            .lineLimit(2)
    }

    private var valueText: some View {
        Text(value.grouped)
            .studioText(.uiSm)
            .foregroundStyle(Color.studioText)
            .monospacedDigit()
    }

    private var shareText: some View {
        Text(share.formatted(.percent.precision(.fractionLength(1))))
            .studioText(.uiSm)
            .foregroundStyle(Color.studioText2)
            .monospacedDigit()
    }
}

/// The chart's footprint while it loads.
private struct ChartPlaceholder: View {
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 220

    var body: some View {
        RoundedRectangle(cornerRadius: StudioRadius.md, style: .continuous)
            .fill(Color.studioSurface2)
            .frame(maxWidth: .infinity, minHeight: height)
            .overlay { ProgressView() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Loading"))
    }
}

#Preview("Link statistics") {
    let client = APIClient(baseURL: AppConfiguration.preview.apiBaseURL)
    let model = StatisticsModel(client: client, target: .link(22),
                                overview: .sample(), breakdown: StatisticsRow.sampleCountries)
    NavigationStack {
        StatisticsScreen(model: model, subtitle: "card.site/spring-menu")
    }
    .environment(AppModel(configuration: .preview))
}

#Preview("All, empty") {
    let client = APIClient(baseURL: AppConfiguration.preview.apiBaseURL)
    let model = StatisticsModel(client: client, target: .all,
                                overview: .init(days: [], start: .now, end: .now), breakdown: [])
    NavigationStack {
        StatisticsScreen(model: model)
    }
    .environment(AppModel(configuration: .preview))
}
