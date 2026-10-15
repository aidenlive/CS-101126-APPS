import XCTest

/// Walks every main screen against the fixture server and attaches a
/// screenshot of each, named `<platform>-<device>-<appearance>-<textsize>-<screen>`.
///
/// Screens that follow on from each other share one launch (signed out;
/// the top-level destinations; Links with its editor and detail; QR codes
/// with the builder; Pages with the editor). Every launch starts from the
/// same seeded data. A screen that can't be reached from where the previous
/// one left off is retried once on a fresh launch, so one stuck screen
/// records a failure without spoiling the next. One test per variant, so CI
/// and Xcode can run them separately
/// (`-only-testing:CardsiteUITests/ScreenshotTests/testLight`).
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

    /// The launches of one walk, in order. Every `Screen` appears once.
    static let launches: [[Screen]] = [
        [.signIn, .signUp],
        [.home, .statistics, .workspace, .inbox, .uploads, .account, .settings],
        [.links, .linkCreate, .linkDetail],
        [.qrCodes, .qrBuilder],
        [.pages, .pageEditor],
    ]

    func testLight() {
        walk(.light)
    }

    func testDark() {
        walk(.dark)
    }

    func testLargeText() {
        walk(.largeText)
    }

    /// Empty states, light only: a fresh account with nothing in it. One launch.
    func testEmptyStates() {
        continueAfterFailure = true
        let screens: [Destination] = [.home, .links, .qrCodes, .pages, .inbox, .uploads]
        let names: [Destination: String] = [
            .home: "home", .links: "links", .qrCodes: "qr-codes", .pages: "pages", .inbox: "inbox", .uploads: "uploads",
        ]
        run(screens, variant: .light, empty: true,
            name: { (names[$0] ?? $0.rawValue) + "-empty" },
            reach: { destination, ui in ui.open(destination) },
            failure: { destination in "Couldn't open \(destination.rawValue) on an empty account" })
        Harness.attachMissingIdentifiers(to: self)
    }

    private func walk(_ variant: Variant) {
        continueAfterFailure = true
        for screens in Self.launches {
            run(screens, variant: variant, signedOut: screens.allSatisfy { $0.isSignedOut },
                name: { $0.rawValue },
                reach: { screen, ui in show(screen, in: ui) },
                tidy: { screen, ui in tidy(after: screen, in: ui) },
                failure: { screen in "Couldn't reach \(screen.rawValue) (\(variant.appearance), \(variant.textSize))" })
        }
        Harness.attachMissingIdentifiers(to: self)
    }

    /// Captures `steps` in one launch. A step that fails after the first is
    /// retried on a fresh launch; a step that still fails is captured as
    /// `<name>-unreached` (what is on screen shows where navigation
    /// stopped), recorded, and the next step starts on a fresh launch.
    private func run<Step>(
        _ steps: [Step],
        variant: Variant,
        signedOut: Bool = false,
        empty: Bool = false,
        name: (Step) -> String,
        reach: (Step, Harness) -> Bool,
        tidy: (Step, Harness) -> Bool = { _, _ in true },
        failure: (Step) -> String
    ) {
        var ui: Harness?
        var isFresh = false
        func launch() -> Harness {
            ui?.app.terminate()
            let fresh = Harness(test: self, variant: variant, signedOut: signedOut, empty: empty)
            ui = fresh
            isFresh = true
            return fresh
        }

        for step in steps {
            var current = ui ?? launch()
            var reached = reach(step, current)
            if !reached && !isFresh {
                current = launch()
                reached = reach(step, current)
            }
            isFresh = false
            if reached {
                current.capture(name(step))
                if !tidy(step, current) {
                    current.app.terminate()
                    ui = nil
                }
            } else {
                current.capture(name(step) + "-unreached")
                XCTFail(failure(step))
                current.app.terminate()
                ui = nil
            }
        }
        ui?.app.terminate()
    }

    /// Navigates to `screen` from launch, or from where the previous screen
    /// in its launch left off. Returns false if it couldn't.
    private func show(_ screen: Screen, in ui: Harness) -> Bool {
        switch screen {
        case .signIn:
            return ui.findAny(["auth.signIn", "auth.toSignUp"], labels: ["Sign In", "Sign in"], timeout: 10) != nil
        case .signUp:
            guard ui.tap("auth.toSignUp", labels: ["Create an Account"], timeout: 10) else { return false }
            return ui.find("auth.signUp", labels: ["Create Account", "Create your account"]) != nil
        case .home:
            return ui.open(.home)
        case .links:
            guard ui.open(.links) else { return false }
            return ui.find("links.row.0", labels: ["launch"]) != nil
        case .linkDetail:
            guard ui.open(.links), ui.tap("links.row.0", labels: ["launch"]) else { return false }
            return ui.find("link.detail", labels: ["https://example.com/blog/introducing-northwind"]) != nil
        case .linkCreate:
            guard ui.open(.links) else { return false }
            if !ui.tap("links.create", labels: ["New Short Link"], timeout: 3) {
                #if os(macOS)
                ui.app.typeKey("n", modifierFlags: .command)
                #else
                return false
                #endif
            }
            return ui.findAny(["link.editor.slug", "link.editor.destination", "link.editor"]) != nil
        case .statistics:
            return ui.open(.statistics)
        case .qrCodes:
            guard ui.open(.qrCodes) else { return false }
            return ui.find("qr.row.0", labels: ["Spring menu table card"]) != nil
        case .qrBuilder:
            guard ui.open(.qrCodes) else { return false }
            if !ui.tap("qr.create", labels: ["New QR Code"], timeout: 3) {
                #if os(macOS)
                ui.app.typeKey("n", modifierFlags: [.command, .shift])
                #else
                return false
                #endif
            }
            return ui.findAny(["qr.editor.name", "qr.editor.save", "qr.editor"]) != nil
        case .pages:
            guard ui.open(.pages) else { return false }
            return ui.find("pages.row.0", labels: ["avery"]) != nil
        case .pageEditor:
            guard ui.open(.pages), ui.tap("pages.row.0", labels: ["avery"]) else { return false }
            // The editor's own controls first: a label search would walk
            // the web preview's DOM, which timed out on the iPhone.
            return ui.findAny(["page.editor", "page.editor.add", "page.editor.more", "page.editor.status"]) != nil
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

    /// Leaves the app where the next screen in the launch can start. False
    /// means it couldn't, and the next screen gets a fresh launch.
    private func tidy(after screen: Screen, in ui: Harness) -> Bool {
        switch screen {
        case .linkCreate:
            return ui.dismissSheet(until: ui.element("link.editor.slug"))
        default:
            return true
        }
    }
}
