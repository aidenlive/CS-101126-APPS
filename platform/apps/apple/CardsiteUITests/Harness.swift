import XCTest
#if canImport(UIKit)
import UIKit
#endif

/// The app's main destinations. Raw values match the app's `Destination`
/// registry; a sidebar row, tab or "More" row is found by `nav.<rawValue>`
/// and the destination's root view by `screen.<rawValue>`.
enum Destination: String, CaseIterable {
    case home, links, statistics, qrCodes, pages, account, settings, workspace, inbox, uploads

    /// Visible titles to fall back on when an identifier is missing.
    var labels: [String] {
        switch self {
        case .home: ["Home", "Dashboard", "Overview"]
        case .links: ["Links", "Short Links", "Short links"]
        case .statistics: ["Statistics", "Analytics"]
        case .qrCodes: ["QR Codes", "QR codes"]
        case .pages: ["Pages", "Bio Pages", "Bio pages"]
        case .account: ["Account"]
        case .settings: ["Settings", "Preferences"]
        case .workspace: ["Workspace", "Workspaces", "Team"]
        case .inbox: ["Inbox", "Notifications"]
        case .uploads: ["Uploads"]
        }
    }
}

/// Appearance and text size for one pass of screenshots.
struct Variant: Sendable {
    let appearance: String
    let textSize: String

    static let light = Variant(appearance: "light", textSize: "default")
    static let dark = Variant(appearance: "dark", textSize: "default")
    static let largeText = Variant(appearance: "light", textSize: "ax5")

    var launchArguments: [String] {
        var arguments = ["-AppleInterfaceStyle", appearance == "dark" ? "Dark" : "Light"]
        if textSize == "ax5" {
            arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        return arguments
    }
}

/// Drives one launch of the app in fixture mode. Create one per launch;
/// every lookup tries the accessibility identifier first, then visible
/// labels, and records identifiers it had to fall back from.
@MainActor
struct Harness {
    let app: XCUIApplication
    let test: XCTestCase
    let variant: Variant

    /// Identifiers looked up and not found, across the test run, so a run
    /// can report which ones the app still needs.
    static var missingIdentifiers: Set<String> = []

    init(test: XCTestCase, variant: Variant = .light, signedOut: Bool = false, empty: Bool = false) {
        self.test = test
        self.variant = variant
        app = XCUIApplication()
        var arguments = [signedOut ? "-CardsiteFixturesSignedOut" : "-CardsiteFixtures"]
        if empty { arguments.append("-CardsiteFixturesEmpty") }
        arguments += variant.launchArguments
        arguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ApplePersistenceIgnoreState", "YES"]
        app.launchArguments = arguments
        app.launch()
    }

    // MARK: Finding things

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Candidates for a visible label, most specific first: tab and sidebar
    /// items, then buttons and cells, then anything.
    private func labelled(_ label: String) -> [XCUIElement] {
        [
            app.tabBars.buttons[label],
            app.outlines.staticTexts[label],
            app.buttons[label],
            app.cells.staticTexts[label],
            app.menuItems[label],
            app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch,
        ]
    }

    /// Polls until the identifier, or failing that one of the labels, exists.
    func find(_ identifier: String, labels: [String] = [], timeout: TimeInterval = 8) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        var first = true
        repeat {
            let byID = element(identifier)
            let found = first ? byID.waitForExistence(timeout: min(2, timeout)) : byID.exists
            if found { return byID }
            first = false
            for label in labels {
                if let match = labelled(label).first(where: { $0.exists }) {
                    Self.missingIdentifiers.insert(identifier)
                    return match
                }
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        Self.missingIdentifiers.insert(identifier)
        return nil
    }

    /// Finds and taps. Scrolls on iOS when the element is off screen.
    @discardableResult
    func tap(_ identifier: String, labels: [String] = [], timeout: TimeInterval = 8) -> Bool {
        guard let target = find(identifier, labels: labels, timeout: timeout) else { return false }
        reveal(target)
        target.tap()
        return true
    }

    func reveal(_ target: XCUIElement) {
        #if os(iOS)
        var tries = 0
        while !target.isHittable && tries < 6 {
            app.swipeUp()
            tries += 1
        }
        #endif
    }

    /// Replaces a text field's contents.
    func replaceText(in field: XCUIElement, with text: String) {
        reveal(field)
        #if os(macOS)
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        #else
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        #endif
        field.typeText(text)
    }

    /// The text field with `identifier`, or the first text field labelled
    /// one of `labels`.
    func textField(_ identifier: String, labels: [String] = [], timeout: TimeInterval = 8) -> XCUIElement? {
        let byID = element(identifier)
        if byID.waitForExistence(timeout: min(3, timeout)) {
            // The identifier may sit on a container (a StudioTextField); use the field inside.
            if byID.elementType == .textField || byID.elementType == .secureTextField || byID.elementType == .textView {
                return byID
            }
            let inner = byID.descendants(matching: .textField).firstMatch
            if inner.exists { return inner }
            let secure = byID.descendants(matching: .secureTextField).firstMatch
            if secure.exists { return secure }
            return byID
        }
        Self.missingIdentifiers.insert(identifier)
        for label in labels {
            for candidate in [app.textFields[label], app.secureTextFields[label], app.textViews[label]] where candidate.exists {
                return candidate
            }
            let byPlaceholder = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", label)).firstMatch
            if byPlaceholder.exists { return byPlaceholder }
            let securePlaceholder = app.secureTextFields.matching(NSPredicate(format: "placeholderValue == %@", label)).firstMatch
            if securePlaceholder.exists { return securePlaceholder }
        }
        return nil
    }

    /// True once any static text, button or field shows `text`.
    func waitForText(_ text: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let fieldPredicate = NSPredicate(format: "value CONTAINS %@", text)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.staticTexts.matching(predicate).firstMatch.exists
                || app.buttons.matching(predicate).firstMatch.exists
                || app.cells.matching(predicate).firstMatch.exists
                || app.textFields.matching(fieldPredicate).firstMatch.exists
                || app.textViews.matching(fieldPredicate).firstMatch.exists {
                return true
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return false
    }

    /// True once a row whose identifier starts with `prefix` (e.g.
    /// `links.row.`) shows `text`, on itself or on a child.
    func rowExists(prefix: String, containing text: String, timeout: TimeInterval = 10) -> Bool {
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        let labelled = NSPredicate(format: "label CONTAINS %@", text)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if rows.matching(labelled).firstMatch.exists || rows.containing(labelled).firstMatch.exists {
                return true
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return false
    }

    // MARK: Navigation

    /// Opens a destination from the tab bar, sidebar or "More", and waits
    /// for its root view.
    @discardableResult
    func open(_ destination: Destination) -> Bool {
        let identifier = "nav.\(destination.rawValue)"
        if tap(identifier, labels: destination.labels, timeout: 5), waitForScreen(destination) {
            return true
        }
        // iPhone: secondary destinations live under "More".
        if tap("nav.more", labels: ["More"], timeout: 2),
           tap(identifier, labels: destination.labels, timeout: 4),
           waitForScreen(destination) {
            return true
        }
        // iPad: a collapsed sidebar.
        if tap("nav.sidebar", labels: ["Show Sidebar", "Sidebar", "ToggleSidebar"], timeout: 2),
           tap(identifier, labels: destination.labels, timeout: 4),
           waitForScreen(destination) {
            return true
        }
        #if os(macOS)
        // Mac: Settings is its own scene (⌘,).
        if destination == .settings {
            app.typeKey(",", modifierFlags: .command)
            return waitForScreen(destination)
        }
        #endif
        return false
    }

    /// Waits for `screen.<rawValue>`; without it, accepts a navigation bar
    /// titled like the destination.
    func waitForScreen(_ destination: Destination, timeout: TimeInterval = 8) -> Bool {
        let identifier = "screen.\(destination.rawValue)"
        if element(identifier).waitForExistence(timeout: timeout) { return true }
        Self.missingIdentifiers.insert(identifier)
        #if os(iOS)
        return destination.labels.contains { app.navigationBars[$0].exists }
        #else
        // macOS has no navigation bar element; the tap itself is the evidence.
        return true
        #endif
    }

    /// Goes back one level in a navigation stack. A no-op where the list and
    /// detail sit side by side.
    func goBack() {
        #if os(iOS)
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists && back.isHittable { back.tap() }
        #endif
    }

    // MARK: Capture

    /// Waits for spinners to clear and animations to settle, then attaches
    /// a screenshot named `<platform>-<device>-<appearance>-<textsize>-<screen>`.
    func capture(_ screen: String) {
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline && (app.activityIndicators.firstMatch.exists || app.progressIndicators.firstMatch.exists) {
            Thread.sleep(forTimeInterval: 0.3)
        }
        Thread.sleep(forTimeInterval: 0.8)
        #if os(macOS)
        let window = app.windows.firstMatch
        let shot = window.exists ? window.screenshot() : XCUIScreen.main.screenshot()
        #else
        let shot = XCUIScreen.main.screenshot()
        #endif
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = [Device.platform, Device.model, variant.appearance, variant.textSize, screen].joined(separator: "-")
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }

    /// Attaches the identifiers this run had to fall back from, so the
    /// integrator can add them.
    static func attachMissingIdentifiers(to test: XCTestCase) {
        guard !missingIdentifiers.isEmpty else { return }
        let attachment = XCTAttachment(string: missingIdentifiers.sorted().joined(separator: "\n"))
        attachment.name = "missing-identifiers-\(Device.platform)-\(Device.model)"
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }
}

/// Names the platform and device for screenshot file names.
@MainActor
enum Device {
    static var platform: String {
        #if os(macOS)
        return "macos"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipados" : "ios"
        #endif
    }

    /// e.g. `iphone17promax`, `ipadpro13inchm5`, `mac`.
    static var model: String {
        #if os(macOS)
        return "mac"
        #else
        let name = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.model
        return String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
        #endif
    }
}
