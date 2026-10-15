import SwiftUI
import WebKit
import StudioKit
import CardsiteKit

/// The public page as visitors see it: the canvas's content. Reloaded
/// whenever `revision` moves (after every save, and on Reload).
///
/// It draws only the page and its own loading and failure states; the
/// canvas around it (full-bleed on iPhone, an artboard on iPad and Mac)
/// belongs to the editor.
struct PageCanvasPreview: View {
    @Environment(AppModel.self) private var app
    let page: BioPage
    let revision: Int
    /// iPhone: room under the page's last block for the floating palette.
    var bottomInset: CGFloat = 0
    let reload: () -> Void

    @State private var isLoading = false
    @State private var failure: String? = nil

    var body: some View {
        ZStack {
            if let url = app.addresses.url(for: page.slug) {
                PageWebView(url: url, revision: revision, bottomInset: bottomInset,
                            isLoading: $isLoading, failure: $failure)
                    // One element, not the page's DOM: the blocks are
                    // edited (and read) from the palette and outline, and a
                    // deep web tree stalled accessibility queries.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Preview of \(app.addresses.display(for: page.slug))"))
                    .accessibilityHint(Text("The blocks are listed in the outline."))
                if let failure {
                    Color.studioBg
                    StudioEmptyState(
                        systemImage: "wifi.exclamationmark",
                        title: String(localized: "Couldn’t load the preview"),
                        message: failure,
                        compact: true
                    ) {
                        StudioButton(String(localized: "Try Again"), systemImage: "arrow.clockwise", variant: .outline) {
                            reload()
                        }
                    }
                    .padding(StudioSpace.s5)
                } else if isLoading {
                    ProgressView()
                        .padding(StudioSpace.s3)
                        .background(Color.studioSurface, in: Capsule())
                        .studioElevation(.raised)
                        .accessibilityLabel(Text("Loading preview"))
                }
            } else {
                Color.studioBg
                StudioEmptyState(
                    systemImage: "eye.slash",
                    title: String(localized: "No preview"),
                    message: String(localized: "This page has no public address to show."),
                    compact: true
                ) {
                    EmptyView()
                }
                .padding(StudioSpace.s5)
            }
        }
    }
}

// MARK: - WKWebView

/// A WKWebView that loads `url` whenever `url` or `revision` changes,
/// bypassing the cache so a save shows at once.
///
/// Main-actor isolated in its primary declaration: the representable
/// conformance lives in a platform extension, which would not isolate
/// `makeCoordinator()` (it builds the main-actor `Coordinator`).
@MainActor
struct PageWebView {
    let url: URL
    let revision: Int
    var bottomInset: CGFloat = 0
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
            #if DEBUG
            // Fixture runs (UI tests, the demo scheme) never reach the
            // network: the public address belongs to no fixture server, and
            // whatever a live host serves would make CI depend on it.
            if FixtureMode.isEnabled {
                webView.loadHTMLString(Self.fixtureHTML(for: parent.url), baseURL: nil)
                return
            }
            #endif
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

        #if DEBUG
        /// A plain stand-in page in the system's own colours and type.
        static func fixtureHTML(for url: URL) -> String {
            let address = (url.host() ?? "") + url.path()
            return """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>:root{color-scheme:light dark;font:-apple-system-body;}body{margin:0;padding:48px 24px;text-align:center}
            h1{font:-apple-system-title1;margin:0 0 8px}p{margin:0;opacity:.6}</style></head>
            <body><h1>\(address)</h1><p>Fixture preview. A real build shows the live page here.</p></body></html>
            """
        }
        #endif

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
        #if os(iOS) || os(visionOS)
        // One accessibility element, so assistive tech and UI tests don't
        // walk the page's DOM through the web process on the main thread
        // (CI: "process main thread busy" on the iPhone editor). The blocks
        // are read and edited in the outline and palette.
        webView.isAccessibilityElement = true
        webView.accessibilityLabel = String(localized: "Page preview")
        #endif
        applyInsets(to: webView)
        context.coordinator.load(in: webView)
        return webView
    }

    @MainActor
    private func updateWebView(_ webView: WKWebView, _ context: Context) {
        context.coordinator.parent = self
        applyInsets(to: webView)
        context.coordinator.load(in: webView)
    }

    /// Lets the page's last block scroll clear of the floating palette.
    @MainActor
    private func applyInsets(to webView: WKWebView) {
        #if os(iOS) || os(visionOS)
        let scrollView = webView.scrollView
        guard scrollView.contentInset.bottom != bottomInset else { return }
        scrollView.contentInset.bottom = bottomInset
        scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
        #endif
    }
}

#if os(iOS) || os(visionOS)
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
