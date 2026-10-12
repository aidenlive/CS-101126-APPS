import SwiftUI

/// Cardsite on Apple Watch: recent links with their clicks, a link's day
/// and week, and a full-screen QR code to show someone. It needs the
/// iPhone app to sign in (the session arrives over WatchConnectivity).
@main
struct CardsiteWatchApp: App {
    @State private var session = WatchSession()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(session)
                .tint(WatchPalette.accentLine)
                .task { session.activate() }
        }
    }
}
