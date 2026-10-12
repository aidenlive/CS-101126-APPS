#if DEBUG
import SwiftUI
import CardsiteKit

/// Fixture mode: the app runs against ``FixtureTransport`` instead of the
/// network, so UI tests and screenshots need no server. Debug builds only.
///
/// Launch arguments (read once, at launch):
/// - `-CardsiteFixtures`: signed in as the fixture user, with a full account.
/// - `-CardsiteFixturesSignedOut`: fixture mode, starting on the sign-in screen.
///   Sign in with any email and ``password``.
/// - `-CardsiteFixturesEmpty`: an account with nothing in it, for empty states.
/// - `-CardsiteFixtureLatency <seconds>`: delay every response, to see
///   loading states. Defaults to none.
/// - `-AppleInterfaceStyle Dark` (or `Light`): appearance. macOS honours it natively;
///   ``fixtureOverrides()`` applies it on iOS too.
/// - `-UIPreferredContentSizeCategoryName <UICTContentSizeCategory…>`: text
///   size. iOS honours it natively; ``fixtureOverrides()`` applies it on macOS.
enum FixtureMode {
    static let arguments = ProcessInfo.processInfo.arguments

    static let isEnabled = arguments.contains("-CardsiteFixtures") || arguments.contains("-CardsiteFixturesSignedOut")
    static let startsSignedOut = arguments.contains("-CardsiteFixturesSignedOut")
    static let isEmpty = arguments.contains("-CardsiteFixturesEmpty")

    /// The fixture account's password. Anything else is "wrong".
    static let password = "cardsite-fixtures"
    /// The code that `POST /auth/2fa/verify` accepts.
    static let twoFactorCode = "123456"

    /// A well-formed JWT whose `exp` is 2100-01-01, so `JWT.isExpired` is
    /// false. The fixture server accepts any bearer token.
    static let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjQxMDI0NDQ4MDAsImlhdCI6MTc5MTczNDQwMCwidXNlcl9pZCI6NH0.Y2FyZHNpdGUtZml4dHVyZS1zaWduYXR1cmU"

    /// Holds the fixture token unless the launch asked to start signed out.
    /// Never the keychain, so fixture runs leave no trace on the device.
    static func tokenStore() -> TokenStore {
        MemoryTokenStore(token: startsSignedOut ? nil : token)
    }

    static var latency: Duration {
        guard let index = arguments.firstIndex(of: "-CardsiteFixtureLatency"),
              arguments.indices.contains(index + 1),
              let seconds = Double(arguments[index + 1]), seconds > 0 else { return .zero }
        return .milliseconds(Int(seconds * 1000))
    }

    /// From `-AppleInterfaceStyle Dark` or `Light` (the argument domain of
    /// `UserDefaults`). Nil follows the system.
    static var colorScheme: ColorScheme? {
        guard isEnabled else { return nil }
        switch UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    /// From `-UIPreferredContentSizeCategoryName`.
    static var dynamicTypeSize: DynamicTypeSize? {
        guard isEnabled, let name = UserDefaults.standard.string(forKey: "UIPreferredContentSizeCategoryName") else { return nil }
        let sizes: [String: DynamicTypeSize] = [
            "UICTContentSizeCategoryXS": .xSmall,
            "UICTContentSizeCategoryS": .small,
            "UICTContentSizeCategoryM": .medium,
            "UICTContentSizeCategoryL": .large,
            "UICTContentSizeCategoryXL": .xLarge,
            "UICTContentSizeCategoryXXL": .xxLarge,
            "UICTContentSizeCategoryXXXL": .xxxLarge,
            "UICTContentSizeCategoryAccessibilityM": .accessibility1,
            "UICTContentSizeCategoryAccessibilityL": .accessibility2,
            "UICTContentSizeCategoryAccessibilityXL": .accessibility3,
            "UICTContentSizeCategoryAccessibilityXXL": .accessibility4,
            "UICTContentSizeCategoryAccessibilityXXXL": .accessibility5,
        ]
        return sizes[name]
    }
}

private struct FixtureOverrides: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if let size = FixtureMode.dynamicTypeSize {
            content
                .preferredColorScheme(FixtureMode.colorScheme)
                .dynamicTypeSize(size)
        } else {
            content
                .preferredColorScheme(FixtureMode.colorScheme)
        }
    }
}

extension View {
    /// Applies the appearance and text size from the launch arguments when
    /// fixture mode is on, so every platform renders the requested variant.
    /// Does nothing otherwise.
    func fixtureOverrides() -> some View {
        modifier(FixtureOverrides())
    }
}
#endif
