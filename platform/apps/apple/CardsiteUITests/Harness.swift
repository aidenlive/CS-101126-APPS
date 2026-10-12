import XCTest
#if canImport(UIKit)
import UIKit
#endif

/// The app's main destinations, mirroring `AppDestination` in
/// `Cardsite/App/Destinations.swift`. Raw values match its raw values.
///
/// How each surface exposes a destination:
/// · The iPad and Mac sidebar, and the tab bar, are drawn by the system from
///   `Tab(...)` items and carry no accessibility identifier; they are found
///   by `title` (sidebar) or `tabTitle` (iPhone tab bar).
/// · iPhone's More list rows carry `nav.<rawValue>`.
/// · The destination's root content carries `screen.<rawValue>`.
enum Destination: String, CaseIterable {
    case home, links, statistics, qrCodes, pages, account, settings, workspace, inbox, uploads

    /// `AppDestination.title`: the sidebar, More and the navigation title.
    var title: String {
        switch self {
        case .home: "Home"
        case .links: "Links"
        case .statistics: "Statistics"
        case .qrCodes: "QR Codes"
        case .pages: "Pages"
        case .account: "Account"
        case .settings: "Preferences"
        case .workspace: "Workspace"
        case .inbox: "Inbox"
        case .uploads: "Uploads"
        }
    }

    /// `AppDestination.tabTitle`: the iPhone tab bar's shorter name.
    var tabTitle: String {
        self == .qrCodes ? "QR" : title
    }

    /// `AppDestination.iPhoneTab == .tab`: a tab of its own on iPhone;
    /// everything else is a row in More.
    var isPhoneTab: Bool {
        switch self {
        case .home, .links, .pages, .qrCodes: true
        default: false
        }
    }

    /// The navigation title, when it is fixed. The workspace screen is
    /// titled with the workspace's name.
    var navigationTitle: String? {
        self == .workspace ? nil : title
    }

    /// Identifiers that only exist while this destination is on screen,
    /// accepted as proof it opened when `screen.<rawValue>` doesn't surface.
    var markers: [String] {
        switch self {
        case .links: ["links.create"]
        case .qrCodes: ["qr.create"]
        case .pages: ["pages.create"]
        case .account: ["account.delete"]
        default: []
        }
    }

    /// The Go menu's ⌘ shortcut on Mac (`AppDestination.shortcut`).
    var macShortcut: String? {
        switch self {
        case .home: "1"
        case .links: "2"
        case .pages: "3"
        case .qrCodes: "4"
        case .statistics: "5"
        case .inbox: "6"
        case .workspace: "7"
        default: nil
        }
    }

    var screenIdentifier: String { "screen.\(rawValue)" }
    var navIdentifier: String { "nav.\(rawValue)" }
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

/// Drives one launch of the app in fixture mode. Create one per launch.
///
/// Lookups poll rather than wait on one query at a time, so whichever
/// signal appears first wins, and a fallback never costs more than its own
/// short timeout. Every lookup tries the accessibility identifier first,
/// then visible text, and records identifiers it had to fall back from.
@MainActor
struct Harness {
    let app: XCUIApplication
    let test: XCTestCase
    let variant: Variant
    /// The launch arguments without a starting destination, for relaunches.
    private let baseArguments: [String]

    /// Identifiers looked up and not found, across the test run, so a run
    /// can report which ones the app still needs.
    static var missingIdentifiers: Set<String> = []

    private static let poll: TimeInterval = 0.25

    init(test: XCTestCase, variant: Variant = .light, signedOut: Bool = false, empty: Bool = false) {
        self.test = test
        self.variant = variant
        app = XCUIApplication()
        var arguments = [signedOut ? "-CardsiteFixturesSignedOut" : "-CardsiteFixtures"]
        if empty { arguments.append("-CardsiteFixturesEmpty") }
        arguments += variant.launchArguments
        arguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ApplePersistenceIgnoreState", "YES"]
        baseArguments = arguments
        app.launchArguments = arguments
        app.launch()
        waitForLaunch()
    }

    /// Relaunches straight onto `destination` (fixture mode's debug-only
    /// `-CardsiteOpen`), for when the tab bar or sidebar can't be driven.
    /// The screenshot is what matters; the navigation is covered by the
    /// journeys.
    private func relaunch(opening destination: Destination) -> Bool {
        app.terminate()
        app.launchArguments = baseArguments + ["-CardsiteOpen", destination.rawValue]
        app.launch()
        waitForLaunch()
        return waitForScreen(destination)
    }

    /// Waits for the first real screen: the sign-in form or the signed-in
    /// shell. The first launch of a run (and a Mac app's first window) can
    /// take several seconds; every later lookup can then use short timeouts.
    private func waitForLaunch(timeout: TimeInterval = 25) {
        #if os(macOS)
        // On the CI Mac a launch sometimes comes up with no window at all
        // (the app runs, the AX tree has no Window). Bring the app forward,
        // then open one from File ▸ New Window, as a user would.
        if !app.windows.firstMatch.waitForExistence(timeout: 8) {
            app.activate()
            if !app.windows.firstMatch.waitForExistence(timeout: 3) {
                let file = app.menuBars.menuBarItems["File"]
                if file.exists {
                    file.click()
                    let newWindow = app.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'New Window'")).firstMatch
                    if newWindow.waitForExistence(timeout: 2) {
                        newWindow.click()
                    } else {
                        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
                    }
                }
                _ = app.windows.firstMatch.waitForExistence(timeout: 8)
            }
        }
        #endif
        _ = poll(timeout) {
            element("auth.signIn").exists
                || element("auth.toSignUp").exists
                || element(Destination.home.screenIdentifier).exists
                || app.tabBars.firstMatch.exists
                || app.outlines.firstMatch.exists
                || app.buttons.matching(Self.text("Sign In")).firstMatch.exists
        }
    }

    // MARK: Matching

    /// Matches visible text. macOS puts a static text's string in `value`
    /// and leaves `label` empty; iOS uses `label`. `==` on a non-string
    /// `value` is simply false, so this is safe on any element type.
    static func text(_ text: String) -> NSPredicate {
        NSPredicate(format: "label == %@ OR title == %@ OR value == %@", text, text, text)
    }

    /// Like ``text(_:)``, also accepting a badge suffix ("Inbox, 2").
    static func title(_ title: String) -> NSPredicate {
        NSPredicate(format: "label == %@ OR title == %@ OR value == %@ OR label BEGINSWITH %@",
                    title, title, title, title + ",")
    }

    /// Polls `condition` until it holds or `timeout` passes. Checks once even
    /// with a zero timeout.
    @discardableResult
    func poll(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if condition() { return true }
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: Self.poll)
        }
    }

    // MARK: Finding things

    func element(_ identifier: String) -> XCUIElement {
        // `<prefix>.row.<n>` means the n-th row on screen: the app keys rows
        // by resource id (`links.row.42`), so match the prefix and index.
        if let range = identifier.range(of: ".row."),
           let index = Int(identifier[range.upperBound...]) {
            let prefix = String(identifier[..<range.upperBound])
            let exact = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@ AND elementType != %@",
                                      identifier, NSNumber(value: XCUIElement.ElementType.switch.rawValue)))
                .firstMatch
            if exact.exists { return exact }
            return app.descendants(matching: .any)
                // Not the row's switch, which inherits the row's identifier
                // and isn't the thing to tap.
                .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND elementType != %@",
                                      prefix, NSNumber(value: XCUIElement.ElementType.switch.rawValue)))
                .element(boundBy: index)
        }
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The first existing element showing `label`, preferring controls and
    /// hittable elements. Nil when nothing shows it.
    private func labelled(_ labels: [String]) -> XCUIElement? {
        for label in labels {
            let named = Self.text(label)
            // `firstMatch` everywhere: "Links" can be in the sidebar and the
            // content at once, and a bare subscript fails on two matches.
            let candidates = [
                app.tabBars.buttons.matching(named).firstMatch,
                app.buttons.matching(named).firstMatch,
                app.cells.matching(named).firstMatch,
                app.menuItems.matching(named).firstMatch,
                app.staticTexts.matching(named).firstMatch,
                app.descendants(matching: .any).matching(named).firstMatch,
            ].filter { $0.exists }
            if let match = candidates.first(where: { $0.isHittable }) ?? candidates.first {
                return match
            }
        }
        return nil
    }

    /// Polls for the identifier, then (after a short head start for the
    /// identifier) for one of the labels.
    func find(_ identifier: String, labels: [String] = [], timeout: TimeInterval = 5) -> XCUIElement? {
        findAny([identifier], labels: labels, timeout: timeout)
    }

    /// Polls for any of `identifiers`, then for one of the labels.
    func findAny(_ identifiers: [String], labels: [String] = [], timeout: TimeInterval = 5) -> XCUIElement? {
        let labelsFrom = Date().addingTimeInterval(min(1, timeout / 2))
        var found: XCUIElement?
        var byLabel = false
        poll(timeout) {
            for identifier in identifiers {
                let candidate = element(identifier)
                if candidate.exists {
                    found = candidate
                    return true
                }
            }
            if !labels.isEmpty, Date() >= labelsFrom, let match = labelled(labels) {
                found = match
                byLabel = true
                return true
            }
            return false
        }
        if found == nil || byLabel { Self.missingIdentifiers.formUnion(identifiers) }
        return found
    }

    /// Like ``find(_:labels:timeout:)``, scrolling down when nothing turns
    /// up: lazy lists and forms (`List`, `Form`) only build the rows near
    /// the screen, so a row further down doesn't exist until it is scrolled to.
    func findScrolling(_ identifier: String, labels: [String] = [], timeout: TimeInterval = 2, swipes: Int = 6) -> XCUIElement? {
        if let found = find(identifier, labels: labels, timeout: timeout) { return found }
        #if os(iOS)
        for _ in 0..<swipes {
            app.swipeUp(velocity: .slow)
            if let found = find(identifier, labels: labels, timeout: 0.5) { return found }
        }
        #endif
        return nil
    }

    /// Finds and taps (clicks on Mac).
    @discardableResult
    func tap(_ identifier: String, labels: [String] = [], timeout: TimeInterval = 5, scrolling: Bool = false) -> Bool {
        let target = scrolling
            ? findScrolling(identifier, labels: labels, timeout: min(timeout, 2))
            : find(identifier, labels: labels, timeout: timeout)
        guard let target else { return false }
        press(target)
        return true
    }

    /// Taps on iOS, clicks on Mac. On iOS an element that exists but sits
    /// off screen is scrolled to first.
    func press(_ target: XCUIElement) {
        #if os(macOS)
        target.click()
        #else
        reveal(target)
        target.tap()
        #endif
    }

    /// iOS only: swipes up while the element exists but isn't hittable.
    /// Costs nothing when the element is already on screen. (XCUITest
    /// scrolls to visible on Mac by itself.)
    func reveal(_ target: XCUIElement, swipes: Int = 4) {
        #if os(iOS)
        var tries = 0
        while tries < swipes && target.exists && !target.isHittable {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
        #endif
    }

    /// Replaces a text field's contents.
    func replaceText(in field: XCUIElement, with text: String) {
        #if os(macOS)
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        #else
        reveal(field)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        #endif
        field.typeText(text)
    }

    /// The text field with `identifier` (on the field, or on a container
    /// such as a StudioTextField with the field inside), or the first text
    /// field labelled or placeholdered one of `labels`.
    func textField(_ identifier: String, labels: [String] = [], timeout: TimeInterval = 5) -> XCUIElement? {
        let editable: [XCUIElement.ElementType] = [.textField, .secureTextField, .textView]
        var found: XCUIElement?
        poll(timeout) {
            for type in editable {
                let field = app.descendants(matching: type).matching(identifier: identifier).firstMatch
                if field.exists {
                    found = field
                    return true
                }
            }
            let container = element(identifier)
            if container.exists {
                for type in editable {
                    let inner = container.descendants(matching: type).firstMatch
                    if inner.exists {
                        found = inner
                        return true
                    }
                }
            }
            return false
        }
        if let found { return found }
        Self.missingIdentifiers.insert(identifier)
        for label in labels {
            let named = NSPredicate(format: "label == %@ OR title == %@ OR placeholderValue == %@", label, label, label)
            for type in editable {
                let field = app.descendants(matching: type).matching(named).firstMatch
                if field.exists { return field }
            }
        }
        return nil
    }

    /// Visible text containing `text`: in `label` everywhere, and in
    /// `value` for Mac static texts and for fields.
    private func showsText(_ text: String) -> Bool {
        let labelled = NSPredicate(format: "label CONTAINS %@", text)
        let valued = NSPredicate(format: "value CONTAINS %@", text)
        if app.staticTexts.matching(labelled).firstMatch.exists
            || app.buttons.matching(labelled).firstMatch.exists
            || app.cells.matching(labelled).firstMatch.exists
            || app.textFields.matching(valued).firstMatch.exists
            || app.textViews.matching(valued).firstMatch.exists {
            return true
        }
        #if os(macOS)
        if app.staticTexts.matching(valued).firstMatch.exists { return true }
        #endif
        return false
    }

    /// True once any static text, button or field shows `text`.
    func waitForText(_ text: String, timeout: TimeInterval = 10) -> Bool {
        poll(timeout) { showsText(text) }
    }

    /// True once a row whose identifier starts with `prefix` (e.g.
    /// `links.row.`) shows `text`, on itself or on a child.
    func rowExists(prefix: String, containing text: String, timeout: TimeInterval = 10) -> Bool {
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        let labelled = NSPredicate(format: "label CONTAINS %@", text)
        #if os(macOS)
        // Only static texts: `value` is a string there, and CONTAINS on a
        // non-string value would raise.
        let valued = NSPredicate(format: "elementType == %@ AND value CONTAINS %@",
                                 NSNumber(value: XCUIElement.ElementType.staticText.rawValue), text)
        #endif
        return poll(timeout) {
            if rows.matching(labelled).firstMatch.exists || rows.containing(labelled).firstMatch.exists {
                return true
            }
            #if os(macOS)
            if rows.containing(valued).firstMatch.exists { return true }
            #endif
            return false
        }
    }

    // MARK: Navigation

    /// Opens a destination the way this device shows it (Mac sidebar, iPad
    /// tab bar or sidebar, iPhone tab bar or More), and waits for it.
    /// Returns at once if it is already on screen.
    @discardableResult
    func open(_ destination: Destination) -> Bool {
        if isShowing(destination) { return true }
        #if os(macOS)
        if openOnMac(destination) { return true }
        #else
        if Device.isPhone ? openOnPhone(destination) : openOnPad(destination) { return true }
        #endif
        return relaunch(opening: destination)
    }

    #if os(macOS)
    private func openOnMac(_ destination: Destination) -> Bool {
        if let row = sidebarRow(destination.title, timeout: 3) {
            // Click the row's cell, not its text.
            let cell = row.elementType == .cell ? row : row.cells.firstMatch
            (cell.exists ? cell : row).click()
            if waitForScreen(destination, sidebarRow: row) { return true }
        }
        // The Go menu (⌘1…⌘7).
        if let key = destination.macShortcut {
            app.typeKey(key, modifierFlags: .command)
            if waitForScreen(destination, timeout: 3) { return true }
        }
        return false
    }
    #else
    /// iPhone (and a compact-width iPad window): the tab bar, or More.
    private func openOnPhone(_ destination: Destination) -> Bool {
        if destination.isPhoneTab {
            guard let tab = tabButton(destination.tabTitle, timeout: 3) else { return false }
            tab.tap()
            return waitForScreen(destination)
        }
        guard let more = tabButton("More", timeout: 3) else { return false }
        more.tap()
        showMoreRoot()
        // By identifier only: a title fallback could hit a section header
        // ("Account" heads the section holding the Account row).
        guard let row = findScrolling(destination.navIdentifier, timeout: 2) else {
            return false
        }
        press(row)
        return waitForScreen(destination)
    }

    /// More keeps its stack between visits: pop back to its list.
    private func showMoreRoot() {
        for _ in 0..<3 {
            if poll(1, { app.navigationBars["More"].exists }) { return }
            let back = app.navigationBars.buttons
                .matching(NSPredicate(format: "label == 'More' OR label == 'Back' OR identifier == 'BackButton'"))
                .firstMatch
            guard back.exists else { return }
            back.tap()
        }
    }

    /// iPad: the tab bar, then the sidebar (showing it if it is hidden),
    /// then the compact layout's More.
    private func openOnPad(_ destination: Destination) -> Bool {
        if let tab = tabButton(destination.title, timeout: 0.5), tab.isHittable {
            tab.tap()
            if waitForScreen(destination, timeout: 4) { return true }
        }
        if let row = sidebarRow(destination.title, timeout: 1.5) {
            press(row)
            if waitForScreen(destination, sidebarRow: row) { return true }
        }
        if tap("nav.sidebar", labels: ["Show Sidebar", "Sidebar", "Toggle Sidebar", "ToggleSidebar"], timeout: 1.5),
           let row = sidebarRow(destination.title, timeout: 2) {
            press(row)
            if waitForScreen(destination, sidebarRow: row) { return true }
        }
        return openOnPhone(destination)
    }

    /// A tab bar button titled `title` (a badge may follow: "More, 2").
    private func tabButton(_ title: String, timeout: TimeInterval) -> XCUIElement? {
        let button = app.tabBars.buttons.matching(Self.title(title)).firstMatch
        return poll(timeout, { button.exists }) ? button : nil
    }
    #endif

    /// The sidebar row titled `title`. Sidebar rows are cells (iPad) or
    /// outline rows (Mac) holding the title as text. Two things make the
    /// obvious lookup wrong, and this avoids both:
    /// · a section header can share a row's title ("Account" heads the
    ///   section that contains the Account row), so the lowest match wins;
    /// · the content can show the same words, so only rows in the leading
    ///   column (the sidebar) count.
    private func sidebarRow(_ title: String, timeout: TimeInterval) -> XCUIElement? {
        let named = Self.title(title)
        #if os(macOS)
        let queries = [
            app.outlines.outlineRows.containing(named),
            app.outlineRows.containing(named),
            app.cells.containing(named),
            app.cells.matching(named),
        ]
        #else
        let queries = [
            app.cells.matching(named),
            app.cells.containing(named),
        ]
        #endif
        var row: XCUIElement?
        poll(timeout) {
            let window = app.windows.firstMatch
            guard window.exists else { return false }
            let bounds = window.frame
            let sidebarEdge = bounds.minX + bounds.width * 0.45
            for query in queries {
                let matches = query.allElementsBoundByIndex.filter { candidate in
                    guard candidate.exists else { return false }
                    let frame = candidate.frame
                    return !frame.isEmpty && frame.maxX <= sidebarEdge
                }
                if let lowest = matches.max(by: { $0.frame.minY < $1.frame.minY }) {
                    row = lowest
                    return true
                }
            }
            return false
        }
        return row
    }

    /// True when the destination is on screen, by the first signal that
    /// surfaces: `screen.<rawValue>`, a marker only that screen has, or
    /// its navigation title (the navigation bar on iOS, the window title
    /// on Mac).
    func isShowing(_ destination: Destination) -> Bool {
        if element(destination.screenIdentifier).exists { return true }
        if destination.markers.contains(where: { element($0).exists }) { return true }
        guard let title = destination.navigationTitle else { return false }
        #if os(macOS)
        return app.windows.matching(NSPredicate(format: "title == %@", title)).firstMatch.exists
            || app.toolbars.staticTexts.matching(Self.text(title)).firstMatch.exists
        #else
        // At accessibility sizes the bar's identifier can drop the title;
        // the large title is still a static text inside the bar.
        return app.navigationBars.matching(identifier: title).firstMatch.exists
            || app.navigationBars.staticTexts.matching(Self.text(title)).firstMatch.exists
        #endif
    }

    /// Waits until the destination is showing (see ``isShowing(_:)``), or
    /// the sidebar row just pressed is selected.
    func waitForScreen(_ destination: Destination, sidebarRow: XCUIElement? = nil, timeout: TimeInterval = 6) -> Bool {
        let shown = poll(timeout) {
            if isShowing(destination) { return true }
            if let sidebarRow, sidebarRow.exists, sidebarRow.isSelected { return true }
            return false
        }
        if !element(destination.screenIdentifier).exists {
            Self.missingIdentifiers.insert(destination.screenIdentifier)
        }
        return shown
    }

    /// Goes back one level in a navigation stack. A no-op where the list and
    /// detail sit side by side.
    func goBack() {
        #if os(iOS)
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists && back.isHittable { back.tap() }
        #endif
    }

    /// Dismisses the frontmost sheet with its Cancel button (Escape on Mac).
    /// True once `gone` no longer exists.
    @discardableResult
    func dismissSheet(until gone: XCUIElement) -> Bool {
        #if os(macOS)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        #endif
        if gone.exists {
            let cancel = app.buttons.matching(Self.text("Cancel")).firstMatch
            if cancel.exists { press(cancel) }
        }
        return poll(3) { !gone.exists }
    }

    // MARK: Capture

    /// Waits briefly for spinners to clear and animations to settle, then
    /// attaches a screenshot named `<platform>-<device>-<appearance>-<textsize>-<screen>`.
    func capture(_ screen: String) {
        poll(3) { !app.activityIndicators.firstMatch.exists && !app.progressIndicators.firstMatch.exists }
        Thread.sleep(forTimeInterval: 0.5)
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

    /// True on iPhone: a tab bar with More, never a sidebar.
    static var isPhone: Bool {
        #if os(macOS)
        return false
        #else
        return UIDevice.current.userInterfaceIdiom == .phone
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
