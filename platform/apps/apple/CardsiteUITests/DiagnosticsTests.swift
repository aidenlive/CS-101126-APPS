import XCTest

/// CI-only probes, skipped unless the runner sets `CARDSITE_DIAG=1`
/// (`TEST_RUNNER_CARDSITE_DIAG=1` on the xcodebuild line). The workflow
/// samples the app while they run.
@MainActor
final class DiagnosticsTests: XCTestCase {

    /// The walk's path to the iPhone page editor: Pages, tap the first
    /// row, then read the tree at once. Opened programmatically and read
    /// 8 s later, the same tree came back in under 3 s.
    func testA_PageEditorAfterTap() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CARDSITE_DIAG"] == "1", "CI diagnosis only")
        let app = XCUIApplication()
        app.launchArguments = ["-CardsiteFixtures", "-CardsiteOpen", "pages"]
        app.launch()
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'pages.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No page row")
        NSLog("[diag] tapping the first page row")
        row.tap()
        report(app, "after-tap")
    }

    /// Statistics at AX5, where the AX5 walk stalled after Home.
    func testB_StatisticsAX5() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CARDSITE_DIAG"] == "1", "CI diagnosis only")
        let app = XCUIApplication()
        app.launchArguments = ["-CardsiteFixtures", "-CardsiteOpen", "statistics",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        sleep(3)
        report(app, "statistics-ax5")
    }

    private func report(_ app: XCUIApplication, _ name: String) {
        let started = Date()
        NSLog("[diag] \(name): reading the tree")
        let tree = app.debugDescription
        let took = Date().timeIntervalSince(started)
        NSLog("[diag] \(name): took \(took) s")
        let attachment = XCTAttachment(string: "\(name) took \(took) s\n\n\(tree)")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
