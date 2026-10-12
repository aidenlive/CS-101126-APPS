import XCTest

/// The device-checklist journeys (docs/launch/native-apple.md), run against
/// the fixture server. Each test is a fresh launch with freshly seeded data,
/// so they are independent and can run in any order.
///
/// The fixture account's password is `cardsite-fixtures`; anything else is
/// wrong. The newest short link is `launch` → https://example.com/blog/introducing-northwind.
@MainActor
final class JourneyTests: XCTestCase {

    /// Create a short link; it then appears in the Links list.
    func testCreateLinkAppearsInList() throws {
        let ui = Harness(test: self)
        XCTAssertTrue(ui.open(.links), "Links didn't open")

        if !ui.tap("links.create", labels: ["New Short Link"], timeout: 3) {
            #if os(macOS)
            ui.app.typeKey("n", modifierFlags: .command)
            #else
            XCTFail("No create button (links.create)")
            #endif
        }
        // The editor's own fields, not its title: "New Short Link" is also
        // the create button's label, so it would match with no editor open.
        XCTAssertNotNil(ui.findAny(["link.editor.slug", "link.editor.destination", "link.editor"]),
                        "The link editor didn't open")

        let slug = try XCTUnwrap(ui.textField("link.editor.slug", labels: ["Address", "Slug", "your-name"]), "No address field")
        ui.replaceText(in: slug, with: "journey-link")
        let destination = try XCTUnwrap(ui.textField("link.editor.destination", labels: ["Destination", "https://"]), "No destination field")
        ui.replaceText(in: destination, with: "https://example.com/journey")
        XCTAssertTrue(ui.tap("link.editor.save", labels: ["Create", "Create Link", "Save"]), "No save button")

        // The app may open the new link after creating it; come back to the list.
        if ui.element("link.detail").waitForExistence(timeout: 3) { ui.goBack() }
        XCTAssertTrue(ui.rowExists(prefix: "links.row.", containing: "journey-link") || ui.waitForText("journey-link"),
                      "The new link isn't in the list")
        capture(ui, "journey-link-created")
    }

    /// Change the newest link's destination; the change survives leaving and
    /// reopening the link.
    func testEditDestination() throws {
        let ui = Harness(test: self)
        try openNewestLink(ui)
        let edited = "https://example.com/edited-by-journey"

        if let field = ui.textField("link.detail.destination", timeout: 5),
           [.textField, .textView].contains(field.elementType) {
            ui.replaceText(in: field, with: edited)
            ui.tap("link.detail.save", labels: ["Save", "Done"], timeout: 3)
        } else {
            XCTAssertTrue(ui.tap("link.detail.changeDestination", labels: ["Change Destination"]), "No way to edit the destination")
            let field = try XCTUnwrap(ui.textField("link.destination.field", labels: ["Destination", "https://"]), "No destination field")
            ui.replaceText(in: field, with: edited)
            XCTAssertTrue(ui.tap("link.destination.save", labels: ["Save"]), "No save button")
        }

        XCTAssertTrue(ui.waitForText("edited-by-journey"), "The new destination isn't shown")
        ui.goBack()
        try openNewestLink(ui)
        XCTAssertTrue(ui.waitForText("edited-by-journey"), "The new destination didn't persist")
        capture(ui, "journey-destination-edited")
    }

    /// Turn the newest link off; it stays off after reopening.
    func testToggleDisabled() throws {
        let ui = Harness(test: self)
        try openNewestLink(ui)

        let toggle = try XCTUnwrap(ui.find("link.detail.enabled", labels: ["Enabled", "Live", "Active"]), "No on/off toggle")
        let before = Self.value(of: toggle)
        flip(toggle, in: ui)

        var after = before
        let deadline = Date().addingTimeInterval(10)
        while after == before && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.3)
            after = Self.value(of: toggle)
        }
        XCTAssertNotEqual(before, after, "The toggle didn't change")

        ui.goBack()
        try openNewestLink(ui)
        let reopened = try XCTUnwrap(ui.find("link.detail.enabled", labels: ["Enabled", "Live", "Active"]))
        XCTAssertEqual(Self.value(of: reopened), after, "The link's state didn't persist")
        capture(ui, "journey-link-disabled")
    }

    /// Make a QR code for the newest link; it appears in the QR list.
    func testCreateQRCodeForLink() throws {
        let ui = Harness(test: self)
        try openNewestLink(ui)
        let name = "Journey QR"

        if ui.tap("link.detail.qr", labels: ["Create QR Code", "New QR Code", "QR Code"], timeout: 5) {
            XCTAssertNotNil(ui.find("qr.editor", labels: ["New QR Code"]), "The QR editor didn't open")
        } else {
            // Fallback: the QR builder with the link's address.
            XCTAssertTrue(ui.open(.qrCodes), "QR Codes didn't open")
            XCTAssertTrue(ui.tap("qr.create", labels: ["New QR Code", "Add"]), "No create button (qr.create)")
            let url = try XCTUnwrap(ui.textField("qr.editor.url", labels: ["URL", "https://"]), "No URL field")
            ui.replaceText(in: url, with: "https://card.site/launch")
        }
        let nameField = try XCTUnwrap(ui.textField("qr.editor.name", labels: ["Name"]), "No name field")
        ui.replaceText(in: nameField, with: name)
        XCTAssertTrue(ui.tap("qr.editor.save", labels: ["Create", "Save"]), "No save button")

        XCTAssertTrue(ui.open(.qrCodes), "QR Codes didn't open")
        XCTAssertTrue(ui.rowExists(prefix: "qr.row.", containing: name) || ui.waitForText(name), "The new QR code isn't in the list")
        capture(ui, "journey-qr-created")
    }

    /// Delete account with a wrong password: an error shows and the user
    /// stays signed in (the 401 is a credential check, not an expired session).
    func testDeleteAccountWrongPasswordShowsError() throws {
        let ui = Harness(test: self)
        XCTAssertTrue(ui.open(.account), "Account didn't open")
        // The last row of a lazy Form: it only exists once scrolled to.
        XCTAssertTrue(ui.tap("account.delete", labels: ["Delete Account…", "Delete Account"], scrolling: true),
                      "No delete account button")

        let password = try XCTUnwrap(ui.textField("account.delete.password", labels: ["Your Cardsite password", "Password"]),
                                     "No password field")
        ui.replaceText(in: password, with: "wrong-password")
        XCTAssertTrue(ui.tap("account.delete.confirm", labels: ["Delete My Account"]), "No confirm button")

        // The second confirmation: an alert on iOS, a sheet or dialog on Mac.
        let delete = Harness.text("Delete")
        let confirms = [
            ui.app.alerts.buttons.matching(delete).firstMatch,
            ui.app.sheets.buttons.matching(delete).firstMatch,
            ui.app.dialogs.buttons.matching(delete).firstMatch,
        ]
        var confirm: XCUIElement?
        ui.poll(3) {
            confirm = confirms.first { $0.exists }
            return confirm != nil
        }
        if let confirm { ui.press(confirm) }

        let shown = ui.element("account.delete.error").waitForExistence(timeout: 10) || ui.waitForText("Password is incorrect")
        XCTAssertTrue(shown, "No error for a wrong password")
        XCTAssertFalse(ui.element("auth.signIn").exists, "A wrong password signed the user out")
        capture(ui, "journey-delete-wrong-password")
    }

    // MARK: Helpers

    private func openNewestLink(_ ui: Harness) throws {
        XCTAssertTrue(ui.open(.links), "Links didn't open")
        XCTAssertTrue(ui.tap("links.row.0", labels: ["launch"]), "No first row (links.row.0)")
        XCTAssertNotNil(ui.find("link.detail", labels: ["https://example.com/blog/introducing-northwind"]),
                        "The link detail didn't open (link.detail)")
    }

    /// Taps a toggle on its switch. On iOS a row-wide toggle is tapped at
    /// its trailing edge, where the switch is.
    private func flip(_ toggle: XCUIElement, in ui: Harness) {
        var target = toggle
        if ![.switch, .toggle, .checkBox].contains(toggle.elementType) {
            for inner in [toggle.switches.firstMatch, toggle.checkBoxes.firstMatch, toggle.toggles.firstMatch] where inner.exists {
                target = inner
                break
            }
        }
        ui.reveal(target)
        #if os(macOS)
        target.click()
        #else
        if target.frame.width > 120 {
            target.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        } else {
            target.tap()
        }
        #endif
    }

    private static func value(of element: XCUIElement) -> String {
        element.value.map { String(describing: $0) } ?? ""
    }

    private func capture(_ ui: Harness, _ name: String) {
        ui.capture(name)
        Harness.attachMissingIdentifiers(to: self)
    }
}
