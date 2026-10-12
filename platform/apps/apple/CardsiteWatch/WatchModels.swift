import Foundation
import Observation
import CardsiteKit

/// A screen's data: loading the first time, then loaded (kept while a
/// refresh runs) or failed with the API's own words.
enum WatchLoad<Value: Sendable>: Sendable {
    case loading
    case loaded(Value)
    case failed(message: String, isOffline: Bool)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }
}

extension WatchLoad {
    static func failure(_ error: Error) -> WatchLoad {
        let apiError = error as? APIError
        return .failed(message: apiError?.localizedDescription ?? error.localizedDescription,
                       isOffline: apiError == .offline)
    }
}

/// The home screen: recent short links and stored QR codes.
@MainActor
@Observable
final class WatchHomeModel {
    private(set) var links: WatchLoad<[Resource]> = .loading
    private(set) var qrCodes: WatchLoad<[QRCode]> = .loading

    /// The watch shows the newest few; the phone has the full lists.
    static let limit = 12

    func load(in session: WatchSession) async {
        guard let client = await session.apiClient() else { return }
        async let linkPage = client.links(page: 1, search: nil)
        async let codePage = client.qrCodes(page: 1)

        do {
            let page = try await linkPage
            links = .loaded(Array(page.items.filter { $0.type == LinkKind.shortLink }.prefix(Self.limit)))
        } catch is CancellationError {
            return
        } catch {
            session.handle(error)
            // Keep what's on screen when a refresh fails.
            if links.value == nil { links = .failure(error) }
        }

        do {
            let page = try await codePage
            qrCodes = .loaded(Array(page.items.prefix(Self.limit)))
        } catch is CancellationError {
            return
        } catch {
            session.handle(error)
            if qrCodes.value == nil { qrCodes = .failure(error) }
        }
    }
}

/// One link's clicks: today, the last 7 days (UTC days, as the dashboard
/// counts them) and all time.
@MainActor
@Observable
final class WatchLinkStatsModel {
    struct Stats: Sendable, Equatable {
        let today: Int
        let week: Int
        let allTime: Int
    }

    private(set) var stats: WatchLoad<Stats> = .loading
    let link: Resource

    init(link: Resource) {
        self.link = link
    }

    func load(in session: WatchSession) async {
        guard let client = await session.apiClient() else { return }
        let id = link.id
        let end = Date.now
        let start = Self.utc.date(byAdding: .day, value: -6, to: end) ?? end
        do {
            async let fresh = client.link(id: id)
            async let rows = client.trafficOverview(.link(id), from: start, to: end)
            let (current, days) = try await (fresh, rows)
            let byDate = Dictionary(days.map { ($0.date, $0.pageviews) }, uniquingKeysWith: { first, _ in first })
            stats = .loaded(Stats(today: byDate[CardsiteJSON.dayString(end)] ?? 0,
                                  week: days.reduce(0) { $0 + $1.pageviews },
                                  allTime: current.clicks))
        } catch is CancellationError {
            return
        } catch {
            session.handle(error)
            if stats.value == nil { stats = .failure(error) }
        }
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}

/// What the full-screen code shows: a stored code's own image, or a plain
/// code for a link's short address, rendered by the server because Core
/// Image isn't available on watchOS.
enum WatchQRSource: Hashable, Sendable {
    case stored(QRCode)
    case address(URL, title: String)

    var title: String {
        switch self {
        case .stored(let code): return code.name
        case .address(_, let title): return title
        }
    }
}

@MainActor
@Observable
final class WatchQRModel {
    private(set) var image: WatchLoad<Data> = .loading
    let source: WatchQRSource

    init(source: WatchQRSource) {
        self.source = source
    }

    func load(in session: WatchSession) async {
        guard let client = await session.apiClient() else { return }
        do {
            switch source {
            case .stored(let code):
                // List rows inline the image; the full record is the fallback.
                var png = code.pngData
                if png == nil {
                    let design = try await client.qrCodeDesign(id: code.id)
                    png = design.pngData
                }
                image = png.map { WatchLoad<Data>.loaded($0) }
                    ?? .failed(message: String(localized: "This QR code has no image yet."), isOffline: false)
            case .address(let url, _):
                // `POST /qr-codes/generate` renders without storing anything.
                let payload = QRCodePayload(name: "", type: "url", settings: ["url": .string(url.absoluteString)],
                                            size: 600, errorLevel: "M", foreground: "#000000",
                                            background: "#ffffff", backgroundColorTransparency: 0)
                let preview = try await client.previewQRCode(payload)
                image = preview.pngData.map { WatchLoad<Data>.loaded($0) }
                    ?? .failed(message: String(localized: "Couldn't draw this QR code."), isOffline: false)
            }
        } catch is CancellationError {
            return
        } catch {
            session.handle(error)
            image = .failure(error)
        }
    }
}
