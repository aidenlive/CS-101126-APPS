import SwiftUI
import WidgetKit
import Charts
import StudioKit
import CardsiteKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Widget kinds, also what the app passes to
/// `WidgetCenter.shared.reloadTimelines(ofKind:)`.
enum CardsiteWidgetKind {
    static let linkTraffic = "LinkTraffic"
    static let qrCode = "MyQRCode"
}

// MARK: - Traffic

/// Seven UTC days of pageviews, today included, oldest first: the same
/// days the Statistics screen's 7-day range shows.
enum WeekTraffic {
    static let days = 7

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    static func load(linkID: Int, client: APIClient, now: Date = .now) async throws -> [Int] {
        let start = utc.date(byAdding: .day, value: -(days - 1), to: now) ?? now
        let rows = try await client.trafficOverview(.link(linkID), from: start, to: now)
        return filled(rows, from: start, to: now)
    }

    /// One value per day, zero where the server sent none.
    static func filled(_ rows: [DailyTraffic], from start: Date, to end: Date) -> [Int] {
        let byDate = Dictionary(rows.map { ($0.date, $0.pageviews) }, uniquingKeysWith: { first, _ in first })
        var values: [Int] = []
        var cursor = utc.startOfDay(for: start)
        let last = utc.startOfDay(for: end)
        while cursor <= last {
            values.append(byDate[CardsiteJSON.dayString(cursor)] ?? 0)
            guard let next = utc.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return values
    }
}

extension Int {
    /// "1,234", then "128K" from 100,000, as the dashboard prints figures.
    var clickFigure: String {
        self >= 100_000
            ? formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
            : formatted(.number)
    }
}

/// A seven-day line. The accent line on a soft fill in full colour; the
/// line alone, accentable, when the system tints or desaturates widgets.
struct Sparkline: View {
    let values: [Int]

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { item in
                if renderingMode == .fullColor {
                    AreaMark(x: .value("Day", item.offset), y: .value("Clicks", item.element))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(colors: [Color.studioAccentSoft, Color.studioAccentSoft.opacity(0)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                }
                LineMark(x: .value("Day", item.offset), y: .value("Clicks", item.element))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.studioAccentLine)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(domain: 0...Swift.max(values.count - 1, 1))
        .chartYScale(domain: 0...Swift.max(values.max() ?? 0, 1))
        .widgetAccentable()
        .accessibilityElement()
        .accessibilityLabel(Text("Clicks over the last 7 days"))
        .accessibilityValue(Text(verbatim: values.map { $0.formatted(.number) }.joined(separator: ", ")))
    }
}

// MARK: - States

/// Signed out, empty and failed, in one quiet layout.
struct WidgetMessageView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s2) {
            Image(systemName: systemImage)
                .imageScale(.large)
                .foregroundStyle(Color.studioAccentLine)
                .widgetAccentable()
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(title)
                .studioText(.ui)
                .fontWeight(.semibold)
                .foregroundStyle(Color.studioText)
            Text(message)
                .studioText(.uiSm)
                .foregroundStyle(Color.studioText2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    static func signedOut(_ message: String) -> WidgetMessageView {
        WidgetMessageView(systemImage: "person.crop.circle.badge.exclamationmark",
                          title: String(localized: "Sign in to Cardsite"),
                          message: message)
    }

    static func failed(_ message: String) -> WidgetMessageView {
        WidgetMessageView(systemImage: "exclamationmark.triangle",
                          title: String(localized: "Couldn't load this"),
                          message: message)
    }
}

/// The message a failed timeline shows: offline is said plainly, anything
/// else in the API's own words.
func widgetFailureMessage(_ error: Error) -> String {
    if let error = error as? APIError {
        return error == .offline
            ? String(localized: "You're offline. This updates when you're back.")
            : error.localizedDescription
    }
    if let error = error as? CardsiteIntentError {
        return String(localized: error.localizedStringResource)
    }
    return error.localizedDescription
}

// MARK: - Images

extension Image {
    /// An image from PNG bytes, or nil if they don't decode.
    init?(widgetPNG data: Data) {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        self.init(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        self.init(nsImage: image)
        #else
        return nil
        #endif
    }
}
