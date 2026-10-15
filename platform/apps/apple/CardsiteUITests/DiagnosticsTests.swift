import XCTest

/// CI-only probes, skipped unless the runner sets `CARDSITE_DIAG=1`
/// (`TEST_RUNNER_CARDSITE_DIAG=1` on the xcodebuild line).
@MainActor
final class DiagnosticsTests: XCTestCase {

    /// Opens the first bio page's editor directly, then asks for the
    /// accessibility tree, which left the iPhone app's main thread "busy"
    /// for XCTest. The workflow samples the app meanwhile.
    func testPageEditorAccessibilitySnapshot() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CARDSITE_DIAG"] == "1", "CI diagnosis only")
        let app = XCUIApplication()
        app.launchArguments = ["-CardsiteFixtures", "-CardsiteOpen", "pages", "-CardsiteOpenFirstPage", "YES"]
        app.launch()
        sleep(8)
        let started = Date()
        let tree = app.debugDescription
        let attachment = XCTAttachment(string: "snapshot took \(Date().timeIntervalSince(started)) s\n\n\(tree)")
        attachment.name = "page-editor-tree"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
