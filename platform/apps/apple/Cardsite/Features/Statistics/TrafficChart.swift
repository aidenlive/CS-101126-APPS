import SwiftUI
import Charts
import Accessibility
import StudioKit
import CardsiteKit

/// Pageviews (filled line) against visitors (dashed line), one point per day.
///
/// VoiceOver reads each day as one element ("12 Oct: 41 pageviews,
/// 27 visitors"), and the chart offers an Audio Graph through its chart
/// descriptor.
struct TrafficChart: View {
    let days: [DailyTraffic]

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 220
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Pageviews", point.pageviews)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.studioViz1.opacity(0.22), Color.studioViz1.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .accessibilityHidden(true)

                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Count", point.visitors),
                    series: .value("Series", "Visitors")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.studioViz2)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4]))
                .accessibilityHidden(true)

                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Count", point.pageviews),
                    series: .value("Series", "Pageviews")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.studioViz1)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .accessibilityLabel(Text(point.date, format: .dateTime.day().month(.abbreviated)))
                .accessibilityValue(Text("\(point.pageviews) pageviews, \(point.visitors) visitors"))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Color.studioVizGrid)
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(Color.studioText3)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Color.studioVizGrid)
                AxisValueLabel()
                    .foregroundStyle(Color.studioText3)
            }
        }
        .chartYScale(domain: 0...max(1, maxValue))
        .frame(minHeight: height)
        .animation(reduceMotion ? nil : StudioAnimation.out, value: days)
        .accessibilityLabel(Text("Traffic over time"))
        .accessibilityChartDescriptor(TrafficChartDescriptor(days: days))
    }

    private struct Point: Identifiable {
        let id: String
        let date: Date
        let pageviews: Int
        let visitors: Int
    }

    private var points: [Point] {
        days.compactMap { day in
            day.day.map { Point(id: day.date, date: $0, pageviews: day.pageviews, visitors: day.visitors) }
        }
    }

    private var maxValue: Int {
        days.map { max($0.pageviews, $0.visitors) }.max() ?? 0
    }
}

/// The legend: a solid swatch for pageviews, a dashed one for visitors, so
/// the two read apart without relying on colour.
struct TrafficChartLegend: View {
    var body: some View {
        HStack(spacing: StudioSpace.s4) {
            item(String(localized: "Pageviews"), color: Color.studioViz1, dashed: false)
            item(String(localized: "Visitors"), color: Color.studioViz2, dashed: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Solid line: pageviews. Dashed line: visitors."))
    }

    private func item(_ title: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: StudioSpace.s1) {
            Capsule()
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [3, 3] : []))
                .frame(width: StudioSpace.s4, height: 2)
            Text(title)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText2)
        }
    }
}

/// Audio Graph and VoiceOver chart summary for ``TrafficChart``.
struct TrafficChartDescriptor: AXChartDescriptorRepresentable {
    let days: [DailyTraffic]

    func makeChartDescriptor() -> AXChartDescriptor {
        let labels = days.map(Self.label)
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: String(localized: "Day"),
            categoryOrder: labels
        )
        let top = Double(max(1, days.map { max($0.pageviews, $0.visitors) }.max() ?? 1))
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Count"),
            range: 0...top,
            gridlinePositions: []
        ) { value in
            Int(value).formatted()
        }
        let pageviews = AXDataSeriesDescriptor(
            name: String(localized: "Pageviews"),
            isContinuous: true,
            dataPoints: days.map { AXDataPoint(x: Self.label($0), y: Double($0.pageviews)) }
        )
        let visitors = AXDataSeriesDescriptor(
            name: String(localized: "Visitors"),
            isContinuous: true,
            dataPoints: days.map { AXDataPoint(x: Self.label($0), y: Double($0.visitors)) }
        )
        let total = days.reduce(0) { $0 + $1.pageviews }
        return AXChartDescriptor(
            title: String(localized: "Traffic over time"),
            summary: String(localized: "\(total) pageviews over \(days.count) days."),
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [pageviews, visitors]
        )
    }

    private static func label(_ day: DailyTraffic) -> String {
        day.day?.formatted(.dateTime.day().month(.abbreviated)) ?? day.date
    }
}

#Preview("Traffic chart") {
    VStack(alignment: .leading) {
        TrafficChartLegend()
        TrafficChart(days: StatisticsModel.Overview.sample().days)
    }
    .padding(StudioSpace.s6)
    .background(Color.studioBg)
}
