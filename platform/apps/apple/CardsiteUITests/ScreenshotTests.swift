import XCTest

/// Walks every main screen against the fixture server and attaches a
/// screenshot of each, named `<platform>-<device>-<appearance>-<textsize>-<screen>`.
///
/// Each screen gets a fresh launch, so one screen that can't be reached
/// records a failure without spoiling the next, and every capture starts
/// from the same seeded data. One test per variant, so CI and Xcode can run
/// them separately (`-only-testing:CardsiteUITests/ScreenshotTests/testLight`).
@MainActor
final class ScreenshotTests: XCTestCase {

    enum Screen: String, CaseIterable {
        case signIn = "sign-in"
        case signUp = "sign-up"
        case home
        case links
        case linkDetail = "link-detail"
        case linkCreate = "link-create"
        case statistics
        case qrCodes = "qr-codes"
        case qrBuilder = "qr-builder"
        case pages
        case pageEditor = "page-editor"
        case account
        case settings
        case workspace
        case inbox
        case uploads

        var isSignedOut: Bool { self == .signIn || self == .signUp }
    }

    func testLight() {
        walk(.light)
    }

    func testDark() {
        walk(.dark)
    }

    func testLargeText() {
        walk(.largeText)
    }

    /// Empty states, light only: a fresh account with nothing in it.
    func testEmptyStates() {
        continueAfterFailure = true
        let screens: [(Destination, String)] = [
            (.home, "home"), (.links, "links"), (.qrCodes, "qr-codes"), (.pages, "pages"),
            (.inbox, "inbox"), (.uploads, "uploads"),
        ]
        for (destination, name) in screens {
            let ui = Harness(test: self, variant: .light, empty: true)
            if ui.open(destination) {
                ui.capture(name + "-empty")
            } else {
                XCTFail("Couldn't open \(destination.rawValue) on an empty account")
            }
            ui.app.terminate()
        }
        Harness.attachMissingIdentifiers(to: self)
    }

    private func walk(_ variant: Variant) {
        continueAfterFailure = true
        for screen in Screen.allCases {
            let ui = Harness(test: self, variant: variant, signedOut: screen.isSignedOut)
            if show(screen, in: ui) {
                ui.capture(screen.rawValue)
            } else {
                // Keep what is on screen: it shows where navigation stopped.
                ui.capture(screen.rawValue + "-unreached")
                XCTFail("Couldn't reach \(screen.rawValue) (\(variant.appearance), \(variant.textSize))")
            }
            ui.app.terminate()
        }
        Harness.attachMissingIdentifiers(to: self)
    }

    /// Navigates from launch to `screen`. Returns false if it couldn't.
    private func show(_ screen: Screen, in ui: Harness) -> Bool {
        switch screen {
        case .signIn:
            return ui.find("auth.signIn", labels: ["Sign In"], timeout: 15) != nil
        case .signUp:
            guard ui.tap("auth.toSignUp", labels: ["Create an account"], timeout: 15) else { return false }
            return ui.find("auth.signUp", labels: ["Create Account"]) != nil
        case .home:
            return ui.open(.home)
        case .links:
            guard ui.open(.links) else { return false }
            return ui.find("links.row.0", labels: ["launch"]) != nil
        case .linkDetail:
            return openFirstLink(in: ui)
        case .linkCreate:
            guard ui.open(.links) else { return false }
            if !ui.tap("links.create", labels: ["New Short Link", "New Link", "Add"], timeout: 5) {
                #if os(macOS)
                ui.app.typeKey("n", modifierFlags: .command)
                #else
                return false
                #endif
            }
            return ui.find("link.editor", labels: ["New Short Link", "New Link"]) != nil
        case .statistics:
            return ui.open(.statistics)
        case .qrCodes:
            guard ui.open(.qrCodes) else { return false }
            return ui.find("qr.row.0", labels: ["Spring menu table card"]) != nil
        case .qrBuilder:
            guard ui.open(.qrCodes) else { return false }
            if !ui.tap("qr.create", labels: ["New QR Code", "Add"], timeout: 5) {
                #if os(macOS)
                ui.app.typeKey("n", modifierFlags: [.command, .shift])
                #else
                return false
                #endif
            }
            return ui.find("qr.editor", labels: ["New QR Code"]) != nil
        case .pages:
            guard ui.open(.pages) else { return false }
            return ui.find("pages.row.0", labels: ["avery"]) != nil
        case .pageEditor:
            guard ui.open(.pages), ui.tap("pages.row.0", labels: ["avery"]) else { return false }
            return ui.find("page.editor", labels: ["Hi, I'm Avery"]) != nil
        case .account:
            return ui.open(.account)
        case .settings:
            return ui.open(.settings)
        case .workspace:
            return ui.open(.workspace)
        case .inbox:
            return ui.open(.inbox)
        case .uploads:
            return ui.open(.uploads)
        }
    }

    private func openFirstLink(in ui: Harness) -> Bool {
        guard ui.open(.links), ui.tap("links.row.0", labels: ["launch"]) else { return false }
        return ui.find("link.detail", labels: ["https://example.com/blog/introducing-northwind"]) != nil
    }
}
