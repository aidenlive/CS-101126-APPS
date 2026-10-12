import SwiftUI
import WidgetKit
import AppIntents
import StudioKit
import CardsiteKit

// MARK: - Configuration

/// Edit Widget → QR Code. Left empty, the widget shows the newest code.
struct QRCodeWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "My QR Code" }
    static var description: IntentDescription? {
        IntentDescription("One of your QR codes, ready to scan.")
    }

    @Parameter(title: "QR Code")
    var qrCode: QRCodeEntity?

    init() {}
}

// MARK: - Timeline

struct QRCodeWidgetItem: Hashable, Sendable {
    let id: Int
    let name: String
    let target: String?
    /// The server's rendering. Empty in the placeholder.
    let png: Data
}

struct QRCodeEntry: TimelineEntry {
    enum State: Hashable, Sendable {
        case code(QRCodeWidgetItem)
        /// Signed in, but no QR codes yet.
        case empty
        case signedOut
        case failed(String)
    }

    let date: Date
    let state: State

    static let sample = QRCodeEntry(date: .now, state: .code(
        QRCodeWidgetItem(id: 0, name: "Spring menu", target: "https://card.site/spring-menu", png: Data())
    ))
}

struct QRCodeProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QRCodeEntry {
        .sample
    }

    func snapshot(for configuration: QRCodeWidgetConfiguration, in context: Context) async -> QRCodeEntry {
        if context.isPreview { return .sample }
        return QRCodeEntry(date: .now, state: await load(configuration))
    }

    func timeline(for configuration: QRCodeWidgetConfiguration, in context: Context) async -> Timeline<QRCodeEntry> {
        let state = await load(configuration)
        // A code's image changes only when it's edited, and the cache keeps
        // the widget useful offline, so this refreshes rarely.
        let hours: Double
        switch state {
        case .failed: hours = 0.25
        case .code, .empty, .signedOut: hours = 6
        }
        return Timeline(entries: [QRCodeEntry(date: .now, state: state)],
                        policy: .after(Date.now.addingTimeInterval(hours * 3600)))
    }

    private func load(_ configuration: QRCodeWidgetConfiguration) async -> QRCodeEntry.State {
        let session: IntentSession
        do {
            session = try await IntentSession.open()
        } catch {
            return .signedOut
        }
        do {
            let chosen: QRCodeEntity
            if let configured = configuration.qrCode {
                chosen = configured
            } else {
                let page = try await session.client.qrCodes(page: 1)
                guard let newest = page.items.first else { return .empty }
                chosen = QRCodeEntity(newest)
            }
            let (png, design) = try await QRImageCache.image(for: chosen.id, in: session)
            let current = design.map { QRCodeEntity($0) } ?? chosen
            return .code(QRCodeWidgetItem(id: current.id, name: current.name, target: current.target, png: png))
        } catch CardsiteIntentError.signedOut {
            return .signedOut
        } catch CardsiteIntentError.notFound {
            return .failed(String(localized: "This QR code was deleted. Edit the widget to choose another."))
        } catch APIError.sessionExpired {
            return .signedOut
        } catch {
            return .failed(widgetFailureMessage(error))
        }
    }
}

// MARK: - Widget

struct QRCodeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: CardsiteWidgetKind.qrCode,
                               intent: QRCodeWidgetConfiguration.self,
                               provider: QRCodeProvider()) { entry in
            QRCodeWidgetView(entry: entry)
        }
        .configurationDisplayName("My QR code")
        .description("One of your QR codes, ready to scan.")
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

struct QRCodeWidgetView: View {
    let entry: QRCodeEntry

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
        case .code(let item):
            Group {
                if family == .systemLarge {
                    QRCodeLarge(item: item)
                } else {
                    QRCodeSmall(item: item)
                }
            }
            .widgetURL(CardsiteDeepLink.qrCode(id: item.id).url)
        case .empty:
            WidgetMessageView(systemImage: "qrcode",
                              title: String(localized: "No QR codes yet"),
                              message: String(localized: "Create one in Cardsite to keep it here."))
                .widgetURL(CardsiteDeepLink.home.url)
        case .signedOut:
            WidgetMessageView.signedOut(String(localized: "Open Cardsite to show a QR code here."))
                .widgetURL(CardsiteDeepLink.home.url)
        case .failed(let message):
            WidgetMessageView.failed(message)
                .widgetURL(CardsiteDeepLink.home.url)
        }
    }
}

/// The code itself on a white quiet zone. Scanners need dark modules on a
/// light ground in every appearance, so the tile uses the palette's white
/// rather than a themed surface, and keeps its own colours when the system
/// tints widgets.
private struct QRCodeTile: View {
    let item: QRCodeWidgetItem

    var body: some View {
        Group {
            if let image = Image(widgetPNG: item.png) {
                image
                    .resizable()
                    .interpolation(.none)
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaledToFit()
            } else {
                // Placeholder: no image yet.
                Image(systemName: "qrcode")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.StudioPalette.neutral950)
            }
        }
        .padding(StudioSpace.s2)
        .background(Color.StudioPalette.neutral0,
                    in: RoundedRectangle(cornerRadius: StudioRadius.sm, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(Text("QR code"))
        .accessibilityValue(Text(verbatim: item.target ?? item.name))
    }
}

private struct QRCodeSmall: View {
    let item: QRCodeWidgetItem

    var body: some View {
        VStack(spacing: StudioSpace.s1) {
            QRCodeTile(item: item)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(item.name)
                .studioText(.uiSm)
                .fontWeight(.semibold)
                .foregroundStyle(Color.studioText)
                .lineLimit(1)
        }
    }
}

private struct QRCodeLarge: View {
    let item: QRCodeWidgetItem

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpace.s3) {
            StudioKicker(String(localized: "My QR code"))
            QRCodeTile(item: item)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .studioText(.titleSm)
                    .foregroundStyle(Color.studioText)
                    .lineLimit(1)
                if let target = item.target, !target.isEmpty {
                    Text(verbatim: target)
                        .studioText(.uiSm)
                        .foregroundStyle(Color.studioText2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    QRCodeWidget()
} timeline: {
    QRCodeEntry.sample
    QRCodeEntry(date: .now, state: .signedOut)
}

#Preview("Large", as: .systemLarge) {
    QRCodeWidget()
} timeline: {
    QRCodeEntry.sample
    QRCodeEntry(date: .now, state: .empty)
}
