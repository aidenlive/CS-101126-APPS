import AppIntents

/// The phrases Siri and Spotlight offer without any setup. Every phrase
/// names the app (`.applicationName`), as App Shortcuts require.
///
/// The parameterised phrases ("Show Spring menu in Cardsite") use the
/// entity queries' suggestions. The app refreshes them with
/// `CardsiteShortcuts.updateAppShortcutParameters()` after its link and QR
/// code lists load (see the integration notes).
struct CardsiteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateShortLinkIntent(),
            phrases: [
                "Shorten a link with \(.applicationName)",
                "Create a short link in \(.applicationName)",
                "Make a \(.applicationName) link",
            ],
            shortTitle: "Shorten Link",
            systemImageName: "link.badge.plus"
        )
        AppShortcut(
            intent: ShowQRCodeIntent(),
            phrases: [
                "Show my \(.applicationName) QR code",
                "Show \(\.$qrCode) in \(.applicationName)",
                "Open my QR code in \(.applicationName)",
            ],
            shortTitle: "Show QR Code",
            systemImageName: "qrcode"
        )
        AppShortcut(
            intent: LinkClicksIntent(),
            phrases: [
                "Get link clicks in \(.applicationName)",
                "How many clicks in \(.applicationName)",
                "How many clicks on \(\.$link) in \(.applicationName)",
            ],
            shortTitle: "Link Clicks",
            systemImageName: "chart.bar.xaxis"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .lime }
}
