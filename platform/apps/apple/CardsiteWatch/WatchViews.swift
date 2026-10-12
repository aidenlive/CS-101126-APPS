import SwiftUI
import CardsiteKit
#if canImport(UIKit)
import UIKit
#endif

/// Signed out, or signed in and keyed on the session's scope so a new
/// session or workspace starts every screen fresh.
struct WatchRootView: View {
    @Environment(WatchSession.self) private var session

    var body: some View {
        if session.isSignedIn {
            WatchHomeView()
                .id(session.scope)
        } else {
            WatchSignedOutView()
        }
    }
}

struct WatchSignedOutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: WatchSpace.s2) {
                Image(systemName: "iphone")
                    .font(.title2)
                    .foregroundStyle(WatchPalette.accentLine)
                    .accessibilityHidden(true)
                Text("Sign in on your iPhone")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Open Cardsite on your iPhone and sign in. Your links appear here.")
                    .font(.footnote)
                    .foregroundStyle(WatchPalette.text2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Home

struct WatchHomeView: View {
    @Environment(WatchSession.self) private var session
    @State private var model = WatchHomeModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Recent links") {
                    switch model.links {
                    case .loading:
                        loadingRow
                    case .failed(let message, let isOffline):
                        WatchErrorRow(message: message, isOffline: isOffline) { await model.load(in: session) }
                    case .loaded(let links) where links.isEmpty:
                        Text("No short links yet. Create one in Cardsite on your iPhone.")
                            .font(.footnote)
                            .foregroundStyle(WatchPalette.text2)
                    case .loaded(let links):
                        ForEach(links) { link in
                            NavigationLink(value: link) {
                                WatchLinkRow(link: link, address: session.addresses.display(for: link.slug))
                            }
                        }
                    }
                }

                Section("QR codes") {
                    switch model.qrCodes {
                    case .loading:
                        loadingRow
                    case .failed(let message, let isOffline):
                        WatchErrorRow(message: message, isOffline: isOffline) { await model.load(in: session) }
                    case .loaded(let codes) where codes.isEmpty:
                        Text("No QR codes yet.")
                            .font(.footnote)
                            .foregroundStyle(WatchPalette.text2)
                    case .loaded(let codes):
                        ForEach(codes) { code in
                            NavigationLink(value: WatchQRSource.stored(code)) {
                                Label {
                                    Text(code.name).lineLimit(2)
                                } icon: {
                                    Image(systemName: "qrcode").foregroundStyle(WatchPalette.accentLine)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Cardsite")
            .navigationDestination(for: Resource.self) { link in
                WatchLinkDetailView(link: link)
            }
            .navigationDestination(for: WatchQRSource.self) { source in
                WatchFullScreenQRView(source: source)
            }
            .refreshable { await model.load(in: session) }
            .task { await model.load(in: session) }
        }
        .tint(WatchPalette.accentLine)
    }

    private var loadingRow: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Loading")
    }
}

/// Address on top, clicks under it: the phone's row anatomy, stacked for
/// the watch's width.
struct WatchLinkRow: View {
    let link: Resource
    let address: String

    var body: some View {
        VStack(alignment: .leading, spacing: WatchSpace.hairline) {
            Text(verbatim: address)
                .font(.headline)
                .lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: WatchSpace.s1) {
                Text(link.clicks, format: .number)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(link.isEnabled ? WatchPalette.accent : WatchPalette.text3)
                Text(link.clicks == 1 ? LocalizedStringKey("click") : LocalizedStringKey("clicks"))
                    .font(.footnote)
                    .foregroundStyle(WatchPalette.text2)
                if !link.isEnabled {
                    Text("Off")
                        .font(.footnote)
                        .foregroundStyle(WatchPalette.text3)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WatchErrorRow: View {
    let message: String
    let isOffline: Bool
    let retry: @MainActor () async -> Void

    @State private var isRetrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: WatchSpace.s1) {
            Label(isOffline ? LocalizedStringKey("You're offline") : LocalizedStringKey("Couldn't load this"),
                  systemImage: isOffline ? "wifi.slash" : "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(isOffline ? WatchPalette.text2 : WatchPalette.error)
            Text(message)
                .font(.footnote)
                .foregroundStyle(WatchPalette.text2)
            Button {
                Task {
                    isRetrying = true
                    await retry()
                    isRetrying = false
                }
            } label: {
                if isRetrying {
                    ProgressView()
                } else {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isRetrying)
        }
    }
}

// MARK: - Link detail

struct WatchLinkDetailView: View {
    @Environment(WatchSession.self) private var session
    @State private var model: WatchLinkStatsModel

    init(link: Resource) {
        _model = State(initialValue: WatchLinkStatsModel(link: link))
    }

    private var address: String { session.addresses.display(for: model.link.slug) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: WatchSpace.hairline) {
                    Text(verbatim: address)
                        .font(.headline)
                    if let destination = model.link.destination {
                        Text(verbatim: destination)
                            .font(.footnote)
                            .foregroundStyle(WatchPalette.text2)
                            .lineLimit(3)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Section("Clicks") {
                switch model.stats {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Loading")
                case .failed(let message, let isOffline):
                    WatchErrorRow(message: message, isOffline: isOffline) { await model.load(in: session) }
                case .loaded(let stats):
                    figure("Today", stats.today)
                    figure("Last 7 days", stats.week)
                    figure("All time", stats.allTime)
                }
            }

            if let url = session.addresses.url(for: model.link.slug) {
                Section {
                    NavigationLink(value: WatchQRSource.address(url, title: address)) {
                        Label("Show QR Code", systemImage: "qrcode")
                    }
                }
            }
        }
        .navigationTitle("Link")
        .refreshable { await model.load(in: session) }
        .task { await model.load(in: session) }
    }

    private func figure(_ label: LocalizedStringKey, _ value: Int) -> some View {
        LabeledContent {
            Text(value, format: .number)
                .font(.title3.monospacedDigit())
                .foregroundStyle(WatchPalette.accent)
        } label: {
            Text(label)
        }
    }
}

// MARK: - Full-screen QR

/// The code on white, edge to edge: on an always-dark watch face, a white
/// screen is the brightest the display gets, which is what a scanner needs.
struct WatchFullScreenQRView: View {
    @Environment(WatchSession.self) private var session
    @State private var model: WatchQRModel

    init(source: WatchQRSource) {
        _model = State(initialValue: WatchQRModel(source: source))
    }

    var body: some View {
        ZStack {
            WatchPalette.qrGround
                .ignoresSafeArea()
            switch model.image {
            case .loading:
                ProgressView()
                    .tint(WatchPalette.qrInk)
                    .accessibilityLabel("Loading")
            case .failed(let message, _):
                VStack(spacing: WatchSpace.s1) {
                    Image(systemName: "exclamationmark.triangle")
                        .accessibilityHidden(true)
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    Button("Try Again") { Task { await model.load(in: session) } }
                }
                .foregroundStyle(WatchPalette.qrInk)
                .padding(WatchSpace.s2)
            case .loaded(let png):
                if let image = UIImage(data: png) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(WatchSpace.s1)
                        .accessibilityLabel(Text("QR code for \(model.source.title)"))
                }
            }
        }
        .task { await model.load(in: session) }
    }
}

#if DEBUG
#Preview("Signed out") {
    WatchRootView()
        .environment(WatchSession.preview(signedIn: false))
}

#Preview("Home") {
    WatchRootView()
        .environment(WatchSession.preview())
}

#Preview("QR") {
    NavigationStack {
        WatchFullScreenQRView(source: .address(URL(string: "https://card.site/spring-menu")!, title: "card.site/spring-menu"))
    }
    .environment(WatchSession.preview())
}
#endif
