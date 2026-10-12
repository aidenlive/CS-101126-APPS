import SwiftUI
import WebKit
import StudioKit
import CardsiteKit

/// The public page as visitors see it, reloaded after every save.
struct PagePreviewPane: View {
    @Environment(AppModel.self) private var app
    let page: BioPage
    let revision: Int
    /// Phone-width frame on iPad and Mac; edge to edge in a sheet.
    var isFramed = true

    @State private var isLoading = false
    @State private var failure: String?
    @State private var manualReloads = 0

    var body: some View {
        VStack(spacing: StudioSpace.s4) {
            if !page.isEnabled {
                StudioBanner(
                    lead: String(localized: "This page is off."),
                    message: String(localized: "Visitors get a not-found page until you turn it on, and so does this preview."),
                    tone: .warning
                )
            }
            if let url = app.addresses.url(for: page.slug) {
                previewFrame(for: url)
            }
        }
        .padding(isFramed ? StudioSpace.s6 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.studioBg)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    manualReloads += 1
                } label: {
                    Label("Reload Preview", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    @ViewBuilder
    private func previewFrame(for url: URL) -> some View {
        let web = ZStack {
            PageWebView(url: url, revision: revision + manualReloads, isLoading: $isLoading, failure: $failure)
                .accessibilityLabel(Text("Preview of \(app.addresses.display(for: page.slug))"))
            if let failure {
                Color.studioBg
                StudioEmptyState(
                    systemImage: "wifi.exclamationmark",
                    title: String(localized: "Couldn't load the preview"),
                    message: failure,
                    compact: true
                ) {
                    StudioButton(String(localized: "Try Again"), systemImage: "arrow.clockwise", variant: .outline) {
                        manualReloads += 1
                    }
                }
            } else if isLoading {
                ProgressView()
                    .padding(StudioSpace.s3)
                    .background(Color.studioSurface, in: Capsule())
                    .accessibilityLabel("Loading preview")
            }
        }
        if isFramed {
            web
                .clipShape(RoundedRectangle(cornerRadius: StudioRadius.xl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioRadius.xl, style: .continuous)
                        .strokeBorder(Color.studioBorder, lineWidth: 0.5)
                )
                .studioElevation(.raised)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
        } else {
            web
        }
    }
}

// MARK: - WKWebView

/// A WKWebView that loads `url` whenever `url` or `revision` changes,
/// bypassing the cache so a save shows at once.
struct PageWebView {
    let url: URL
    let revision: Int
    @Binding var isLoading: Bool
    @Binding var failure: String?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: PageWebView
        var loaded: (URL, Int)?

        init(parent: PageWebView) {
            self.parent = parent
        }

        func load(in webView: WKWebView) {
            if let loaded, loaded.0 == parent.url, loaded.1 == parent.revision { return }
            loaded = (parent.url, parent.revision)
            parent.failure = nil
            webView.load(URLRequest(url: parent.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        }

        nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            MainActor.assumeIsolated { parent.isLoading = true }
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            MainActor.assumeIsolated { parent.isLoading = false }
        }

        nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            let message = error.localizedDescription
            let cancelled = (error as NSError).code == NSURLErrorCancelled
            MainActor.assumeIsolated { finish(failing: message, cancelled: cancelled) }
        }

        nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                                 withError error: any Error) {
            let message = error.localizedDescription
            let cancelled = (error as NSError).code == NSURLErrorCancelled
            MainActor.assumeIsolated { finish(failing: message, cancelled: cancelled) }
        }

        private func finish(failing message: String, cancelled: Bool) {
            parent.isLoading = false
            // A reload that replaces an in-flight load cancels it; that is
            // not a failure worth showing.
            guard !cancelled else { return }
            parent.failure = message
        }
    }

    @MainActor
    private func makeWebView(_ context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // A fresh, non-persistent store: the preview never shares cookies
        // or storage with anything else, and never caches a stale page.
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.load(in: webView)
        return webView
    }

    @MainActor
    private func updateWebView(_ webView: WKWebView, _ context: Context) {
        context.coordinator.parent = self
        context.coordinator.load(in: webView)
    }
}

#if os(iOS)
extension PageWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context) }
    func updateUIView(_ webView: WKWebView, context: Context) { updateWebView(webView, context) }
}
#elseif os(macOS)
extension PageWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context) }
    func updateNSView(_ webView: WKWebView, context: Context) { updateWebView(webView, context) }
}
#endif
