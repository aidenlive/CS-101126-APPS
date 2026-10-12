import XCTest
@testable import CardsiteKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Every domain model decoded from the live-captured fixtures, through the
// client call the app makes where there is one. The assertions are the
// values in the fixture files (ContractTests/fixtures), so a change to a
// model that misreads a field fails here.

/// `data` of a fixture, decoded the way the client decodes it.
private func payload<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    let envelope = try CardsiteJSON.decoder().decode(DataEnvelope<T>.self, from: fixture(name).body)
    return try XCTUnwrap(envelope.data, "\(name) has null data")
}

private func stubbed(_ fixtures: String...) throws -> (APIClient, StubTransport) {
    let stub = StubTransport(try fixtures.map { name in
        let f = try fixture(name)
        return (f.status, f.body, [:])
    })
    return (APIClient(baseURL: base, token: "t", transport: stub), stub)
}

private func utcDay(_ raw: String) throws -> Date {
    try XCTUnwrap(CardsiteJSON.parseDay(raw))
}

private let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

// MARK: - Dashboard and statistics

final class DashboardFixtureTests: XCTestCase {
    func testSummary20a() async throws {
        let (api, stub) = try stubbed("20a-statistics-summary-200")
        let summary = try await api.dashboardSummary()
        XCTAssertEqual(summary, DashboardSummary(links: 1, totalClicks: 1))
        XCTAssertEqual(summary.resources, 1)
        XCTAssertFalse(summary.isEmpty)
        XCTAssertEqual(stub.lastRequest?.url?.path, "/api/v1/statistics")
    }

    func testDailySeriesOver20bHas30Rows() throws {
        let rows = try payload([DailyTraffic].self, "20b-statistics-all-overview-200")
        XCTAssertEqual(rows, [DailyTraffic(date: "2026-10-12", pageviews: 1, visitors: 1)])

        let series = DashboardTraffic.daily(rows, from: try utcDay("2026-09-13"), through: try utcDay("2026-10-12"))
        XCTAssertEqual(series.count, 30)
        XCTAssertEqual(series.first?.date, "2026-09-13")
        XCTAssertEqual(series.last, DailyTraffic(date: "2026-10-12", pageviews: 1, visitors: 1))
        XCTAssertEqual(series.reduce(0) { $0 + $1.pageviews }, 1, "the 29 quiet days are zero-filled")
        XCTAssertEqual(Set(series.map(\.date)).count, 30, "one row per day")
    }

    func testStatistics07() async throws {
        let (api, stub) = try stubbed("07a-statistics-overview-empty-200", "07b-statistics-overview-200",
                                     "07c-statistics-referrer-200", "07d-statistics-summary-200")
        let from = try utcDay("2026-10-06")
        let to = try utcDay("2026-10-12")

        let empty = try await api.trafficOverview(.link(22), from: from, to: to)
        XCTAssertEqual(empty, [], "07a: data:null is no traffic")
        let url = try XCTUnwrap(stub.lastRequest?.url)
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertTrue(query.contains(URLQueryItem(name: "type", value: "overview")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "start_date", value: "2026-10-06")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "end_date", value: "2026-10-12")))

        let days = try await api.trafficOverview(.all, from: from, to: to)
        XCTAssertEqual(days, [DailyTraffic(date: "2026-10-12", pageviews: 1, visitors: 1)])
        XCTAssertEqual(stub.lastRequest?.url?.path, "/api/v1/statistics/all")

        let referrers = try await api.trafficBreakdown(.link(22), by: .referrer, from: from, to: to)
        XCTAssertEqual(referrers, [], "07c: no referrer rows")

        let summary = try await api.dashboardSummary()
        XCTAssertEqual(summary.links, 1)
        XCTAssertEqual(summary.totalClicks, 1)
    }
}

// MARK: - Links

final class LinkFixtureTests: XCTestCase {
    func testFullLink22b() async throws {
        let (api, _) = try stubbed("22b-links-get-full-200")
        let link = try await api.linkDetail(id: 22)
        XCTAssertEqual(link.id, 22)
        XCTAssertEqual(link.slug, "ncf-179177059010024")
        XCTAssertEqual(link.destination, "https://example.com/full")
        XCTAssertEqual(link.pixelIDs, [3], "\"[3]\" on the wire")
        XCTAssertEqual(link.projectID, 3)
        XCTAssertEqual(link.domainID, 3)
        XCTAssertEqual(link.splashPageID, 3)
        XCTAssertEqual(link.timezone, "Europe/London")
        XCTAssertEqual(link.scheduledAt, CardsiteJSON.parseTimestamp("2030-01-01T09:00:00Z"))
        XCTAssertEqual(link.scheduledEnd, CardsiteJSON.parseTimestamp("2030-02-01T09:00:00Z"))

        XCTAssertTrue(link.settings.hasPassword)
        XCTAssertEqual(link.settings.clicksLimit, 100)
        XCTAssertEqual(link.settings.redirectStatus, .permanent)
        XCTAssertTrue(link.settings.cloakingEnabled)
        XCTAssertEqual(link.settings.cloakingTitle, "Cloaked")
        XCTAssertEqual(link.settings.expirationURL, "https://example.com/expired")
        XCTAssertTrue(link.settings.forwardQueryParameters)
        XCTAssertTrue(link.settings.sensitiveContent)
        XCTAssertEqual(link.settings.utmSource, "newsletter")
        XCTAssertNil(link.settings.other["password_hash"], "the digest is never kept for sending back")

        XCTAssertEqual(link.displayRules[.countries], ["GB", "US"])
        XCTAssertEqual(link.displayRules[.deviceTypes], ["mobile"])
        XCTAssertEqual(link.displayRules[.languages], ["en"])
        XCTAssertTrue(link.displayRules.narrowsAudience)
    }

    private func changes(password: PasswordChange, domainID: Int?) throws -> LinkChanges {
        let link = try payload(LinkDetail.self, "22b-links-get-full-200")
        return LinkChanges(slug: link.slug, destination: link.destination ?? "", domainID: domainID,
                           projectID: link.projectID, splashPageID: link.splashPageID, settings: link.settings,
                           password: password, displayRules: nil, timezone: link.timezone,
                           scheduledAt: nil, scheduledEnd: nil)
    }

    private func encoded(_ body: [String: JSONValue]) throws -> String {
        String(decoding: try CardsiteJSON.encoder().encode(body), as: UTF8.self)
    }

    func testKeepSendsNoPasswordKey() throws {
        let body = try changes(password: .keep, domainID: 3).body
        let settings = try XCTUnwrap(body["settings"]?.objectValue)
        XCTAssertNil(settings["password"])
        XCTAssertNil(settings["password_hash"])
        XCTAssertFalse(try encoded(body).contains("password"))
        XCTAssertEqual(settings["clicks_limit"], 100)
        XCTAssertEqual(settings["http_status_code"], 301)
        XCTAssertNil(body["display_rules"], "nil rules are left alone")
        XCTAssertNil(body["scheduled_at"])
    }

    func testRemoveSendsEmptyPassword() throws {
        let body = try changes(password: .remove, domainID: 3).body
        XCTAssertEqual(body["settings"]?["password"], .string(""))
        XCTAssertNil(body["settings"]?["password_hash"])
        XCTAssertTrue(try encoded(body).contains("\"password\":\"\""))
    }

    func testSetSendsThePassword() throws {
        let body = try changes(password: .set("open-sesame"), domainID: 3).body
        XCTAssertEqual(body["settings"]?["password"], "open-sesame")
    }

    func testNilDomainEncodesNull() throws {
        let body = try changes(password: .keep, domainID: nil).body
        XCTAssertEqual(body["domain_id"], .null)
        XCTAssertEqual(body["project_id"], 3)
        XCTAssertTrue(try encoded(body).contains("\"domain_id\":null"))
    }
}

// MARK: - Reference

final class ReferenceFixtureTests: XCTestCase {
    func testTargeting21k() async throws {
        let (api, stub) = try stubbed("21k-reference-targeting-200")
        let options = try await api.targetingOptions()
        XCTAssertEqual(options.continents.count, 7)
        XCTAssertEqual(options.countries.count, 250)
        XCTAssertEqual(options.browsers.count, 7)
        XCTAssertEqual(options.operatingSystems.count, 7)
        XCTAssertEqual(options.deviceTypes.count, 3)
        XCTAssertEqual(options.languages.count, 190)
        XCTAssertEqual(options.continents.first, TargetingOption(value: "AF", label: "Africa"))
        XCTAssertEqual(options.countries.first { $0.value == "GB" }?.label, "United Kingdom")
        XCTAssertEqual(options.options(for: .deviceTypes).first?.value, "mobile")
        XCTAssertEqual(options.options(for: .operatingSystems).first, TargetingOption(value: "ios", label: "iOS"))
        XCTAssertNil(stub.lastRequest?.value(forHTTPHeaderField: "Authorization"), "public route")
    }
}

// MARK: - QR codes

final class QRCodeFixtureTests: XCTestCase {
    func testTypes23a() async throws {
        let (api, _) = try stubbed("23a-qr-codes-types-200")
        let types = try await api.qrCodeTypes()
        XCTAssertEqual(types.count, 28)
        XCTAssertEqual(types.first, QRCodeTypeInfo(value: "url", label: "URL", group: "web"))
        XCTAssertEqual(types.last?.value, "information")
        XCTAssertEqual(Set(types.map(\.group)),
                       ["app", "basic", "calendar", "contact", "location", "messaging", "network", "payment", "web"])
    }

    func testPreview23bIsAPNG() throws {
        let preview = try payload(QRCodePreview.self, "23b-qr-codes-generate-200")
        XCTAssertEqual(preview.embeddedData, "https://example.com")
        let png = try XCTUnwrap(preview.pngData)
        XCTAssertEqual(Array(png.prefix(8)), pngMagic)
    }

    func testDesign23dAnd23e() throws {
        for name in ["23d-qr-codes-create-styled-201", "23e-qr-codes-update-200"] {
            let design = try payload(QRCodeDesign.self, name)
            XCTAssertEqual(design.id, 6, name)
            XCTAssertEqual(design.type, "url", name)
            XCTAssertEqual(design.foreground, "#112233", name)
            XCTAssertEqual(design.background, "#ffffff", name)
            XCTAssertEqual(design.linkID, 22, name)
            XCTAssertEqual(design.projectID, 3, name)
            XCTAssertEqual(design.embeddedData, "https://example.com/full", name)
            XCTAssertEqual(design.contentSettings, ["url": "https://example.com/full"], name)
            XCTAssertEqual(design.style["error_level"], "Q", name)
            XCTAssertEqual(design.style["size"], 0, name)
            XCTAssertEqual(design.style["frame"], "", name)
            XCTAssertNil(design.updatedAt, name)
            XCTAssertEqual(Array(try XCTUnwrap(design.pngData, name).prefix(8)), pngMagic, name)
            XCTAssertEqual(design.summary.target, "https://example.com/full", name)
        }
        XCTAssertEqual(try payload(QRCodeDesign.self, "23d-qr-codes-create-styled-201").name, "Styled QR")
        XCTAssertEqual(try payload(QRCodeDesign.self, "23e-qr-codes-update-200").name, "Renamed QR")
    }

    func testPayloadKeys() throws {
        var payload = QRCodePayload(
            name: "Menu", type: "url", settings: ["url": "https://example.com"],
            size: 512, errorLevel: "M", foreground: "#000000", background: "#ffffff",
            backgroundColorTransparency: 0,
            preservedStyle: ["frame": "square", "frame_text": "Scan me", "size": 9000]
        )
        XCTAssertEqual(Set(payload.jsonObject.keys), [
            "name", "type", "settings", "size", "error_level", "foreground", "background",
            "background_color_transparency", "frame", "frame_text",
        ])
        XCTAssertEqual(payload.jsonObject["size"], 512, "a preserved key never overrides a control")
        XCTAssertNil(payload.jsonObject["link_id"])
        XCTAssertNil(payload.jsonObject["embedded_data"])

        payload.linkID = 22
        payload.embeddedData = ""
        XCTAssertEqual(payload.jsonObject["link_id"], 22)
        XCTAssertEqual(payload.jsonObject["embedded_data"], "")

        let json = String(decoding: try CardsiteJSON.encoder().encode(payload), as: UTF8.self)
        XCTAssertTrue(json.contains("\"error_level\":\"M\""), json)
        XCTAssertTrue(json.contains("\"background_color_transparency\":0"), json)
        let decoded = try CardsiteJSON.decoder().decode(JSONValue.self, from: Data(json.utf8))
        XCTAssertEqual(decoded["settings"], ["url": "https://example.com"])
        XCTAssertEqual(decoded, .object(payload.jsonObject), "encoding is the JSON object, flattened")
    }
}

// MARK: - Bio pages

final class BioPageFixtureTests: XCTestCase {
    func testDocument24h() async throws {
        let (api, stub) = try stubbed("24h-biolinks-get-200")
        let document = try await api.bioPage(id: 24)
        XCTAssertEqual(stub.lastRequest?.url?.path, "/api/v1/biolinks/24")
        XCTAssertEqual(document.page.id, 24)
        XCTAssertEqual(document.page.slug, "ncb-179177059010024")
        XCTAssertEqual(document.page.title, "Contract page")
        XCTAssertEqual(document.page.settings["description"], "About us")
        XCTAssertTrue(document.page.directoryIsEnabled)
        XCTAssertEqual(document.blocks.count, 3)
        XCTAssertEqual(document.blocks.map(\.id), [8, 7, 9], "in `order`")
        XCTAssertEqual(document.blocks.map(\.type), ["heading", "link", "email_collector"])
        XCTAssertEqual(document.blocks[1].locationURL, "https://example.com/shop")
        XCTAssertEqual(document.blocks[1].version, 3)
        XCTAssertEqual(document.blocks[0].settings["heading"], "Hello")
    }

    func testBlockTypes24b() async throws {
        let (api, _) = try stubbed("24b-biolink-blocks-types-200")
        let types = try await api.blockTypes()
        XCTAssertEqual(types.count, 85)
        XCTAssertEqual(Set(types.map(\.type)).count, 85, "keys are unique")
        XCTAssertTrue(types.contains { $0.type == "link" })
    }

    func testStaleBlock24eNamesTheLastEditor() async throws {
        let (api, stub) = try stubbed("24e-biolink-blocks-update-409-stale")
        do {
            _ = try await api.updateBlock(id: 7, version: 1, settings: ["name": "Shop"])
            XCTFail("expected a conflict")
        } catch let conflict as BlockConflictError {
            XCTAssertEqual(conflict.lastEditorName, "Native Contract")
            XCTAssertEqual(conflict, BlockConflictError(lastEditorName: "Native Contract"))
        }
        let body = String(decoding: try XCTUnwrap(stub.lastRequest?.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("\"version\":1"), body)
    }

    func testStaleBlockErrorCarriesLastEditor() async throws {
        let (api, _) = try stubbed("24e-biolink-blocks-update-409-stale")
        do {
            try await api.sendIgnoringBody(.put, "api/v1/biolink-blocks/7", body: ["version": 1])
            XCTFail("expected a conflict")
        } catch let error as APIError {
            XCTAssertEqual(error.lastEditorName, "Native Contract")
            guard case .conflict(let title, _, let editor) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(title.hasPrefix("Native Contract changed this block"), title)
            XCTAssertEqual(editor, "Native Contract")
            XCTAssertEqual(BlockConflictError(error)?.lastEditorName, "Native Contract")
        }
    }

    func testConflictWithoutLastEditorFallsBackToTheTitle() {
        let error = BlockConflictError(serverTitle: "Grace changed this block — reload it and reapply your change")
        XCTAssertEqual(error.lastEditorName, "Grace")
        XCTAssertNil(BlockConflictError(serverTitle: "Block was modified elsewhere — reload it").lastEditorName)
        XCTAssertNil(BlockConflictError(APIError.offline))
        XCTAssertNil(APIError.conflict(title: "That address is already taken", message: nil).lastEditorName)
    }
}

// MARK: - Account

final class AccountFixtureTests: XCTestCase {
    func testPreferences26aAnd26b() async throws {
        let (api, stub) = try stubbed("26a-account-preferences-200", "26b-account-preferences-update-200")
        var preferences = try await api.preferences()
        XCTAssertEqual(preferences.values, [:])
        XCTAssertEqual(preferences.resultsPerPage, 25)
        XCTAssertEqual(preferences.orderType, "DESC")
        XCTAssertFalse(preferences.autoCopyLink)

        preferences.resultsPerPage = 50
        preferences.autoCopyLink = true
        let saved = try await api.updatePreferences(preferences)
        XCTAssertEqual(saved.resultsPerPage, 50)
        XCTAssertTrue(saved.autoCopyLink)
        XCTAssertEqual(saved.orderType, "DESC")
        XCTAssertEqual(stub.lastRequest?.httpMethod, "PUT")
    }

    func testTokens26cTo26f() async throws {
        let (api, _) = try stubbed("26c-account-tokens-create-201", "26d-account-tokens-create-400",
                                  "26e-account-tokens-list-200", "26f-account-tokens-revoke-200")
        let created = try await api.createAPIToken(name: "Shortcuts", scopes: ["links:read", "links:write"])
        XCTAssertEqual(created.secret, "<redacted-token>")
        XCTAssertEqual(created.notice, "Store this secret now — it is shown only once.")
        XCTAssertEqual(created.token.id, 3)
        XCTAssertEqual(created.token.scopes, ["links:read", "links:write"])
        XCTAssertEqual(created.token.status(), .active)

        do {
            _ = try await api.createAPIToken(name: "Bad", scopes: ["nope:read"])
            XCTFail("expected a 400")
        } catch let error as APIError {
            XCTAssertEqual(error, .invalid("Unknown scope: nope:read"))
        }

        let list = try await api.apiTokens()
        XCTAssertEqual(list.scopes.count, 28)
        XCTAssertEqual(list.scopes.first, "account:read")
        XCTAssertEqual(list.tokens.map(\.name), ["Shortcuts"])
        XCTAssertNil(list.tokens.first?.lastUsedAt)

        try await api.revokeAPIToken(id: 3)
    }

    func testPassword26gTo26i() async throws {
        let (api, _) = try stubbed("26g-account-password-401", "26h-account-password-400", "26i-account-password-200")
        do {
            try await api.changePassword(current: "wrong", new: "long-enough")
            XCTFail("expected a rejection")
        } catch let error as APIError {
            XCTAssertEqual(error, .rejected("Current password is incorrect"), "a 401 here keeps the session")
        }
        do {
            try await api.changePassword(current: "right", new: "short")
            XCTFail("expected a 400")
        } catch let error as APIError {
            XCTAssertEqual(error, .invalid("New password must be between 8 and 64 characters"))
        }
        try await api.changePassword(current: "right", new: "long-enough")
    }

    func testTwoFactor26jTo26r() async throws {
        let (api, _) = try stubbed("26j-2fa-setup-200", "26k-2fa-status-off-200", "26l-2fa-verify-bad-code",
                                  "26m-2fa-verify-200", "26n-2fa-status-on-200", "26q-2fa-disable-401",
                                  "26r-2fa-disable-200")
        let setup = try await api.startTwoFactorSetup()
        XCTAssertEqual(setup, TwoFactorSetup(secret: "<redacted-totp>", provisioningURL: "<redacted-totp>"))

        let off = try await api.twoFactorStatus()
        XCTAssertEqual(off, TwoFactorStatus(isEnabled: false, remainingRecoveryCodes: 0))

        do {
            _ = try await api.verifyTwoFactor(code: "000000")
            XCTFail("expected a rejection")
        } catch let error as APIError {
            XCTAssertEqual(error, .rejected("Invalid 2FA code"))
        }
        let codes = try await api.verifyTwoFactor(code: "123456")
        XCTAssertEqual(codes.count, 10)

        let on = try await api.twoFactorStatus()
        XCTAssertEqual(on, TwoFactorStatus(isEnabled: true, remainingRecoveryCodes: 10))

        do {
            try await api.disableTwoFactor(password: "wrong")
            XCTFail("expected a rejection")
        } catch let error as APIError {
            XCTAssertEqual(error, .rejected("Invalid password"))
        }
        try await api.disableTwoFactor(password: "right")
    }

    func testTwoFactorSignIn26oAnd26p() async throws {
        let challenge = try payload(JSONValue.self, "26o-auth-login-2fa-required-200")
        XCTAssertEqual(challenge["twofa_required"], true)
        let signedIn = try payload(JSONValue.self, "26p-auth-login-recovery-code-200")
        XCTAssertEqual(signedIn["recovery_codes_remaining"], 9)
        let user = try CardsiteJSON.decoder().decode(User.self, from: CardsiteJSON.encoder().encode(try XCTUnwrap(signedIn["user"])))
        XCTAssertEqual(user.id, 4)
        XCTAssertEqual(user.name, "Native Contract")
        XCTAssertEqual(user.twoFactorEnabled, false)
        XCTAssertEqual(user.timezone, "UTC")
    }
}

// MARK: - Inbox

final class InboxFixtureTests: XCTestCase {
    func testList26sAnd26t() async throws {
        let (api, stub) = try stubbed("26s-internal-notifications-empty-200", "26t-internal-notifications-list-200")
        let empty = try await api.inboxNotifications()
        XCTAssertEqual(empty.items, [])
        XCTAssertEqual(empty.meta, PageMeta(page: 1, perPage: 25, total: 0))
        XCTAssertTrue(stub.lastRequest?.url?.query?.contains("per_page=") == true)

        let page = try await api.inboxNotifications()
        let item = try XCTUnwrap(page.items.first)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(item.id, 4)
        XCTAssertEqual(item.title, "Welcome to Cardsite")
        XCTAssertEqual(item.description, "Your workspace is ready.")
        XCTAssertEqual(item.icon, "fas fa-bell")
        XCTAssertEqual(item.fromWho, "system")
        XCTAssertFalse(item.isRead)
        XCTAssertNotNil(item.createdAt)
        XCTAssertEqual(item.destination(relativeTo: URL(string: "https://cardsite.com")!)?.absoluteString,
                       "https://cardsite.com/dashboard")
    }

    func testUnreadAndMarking26uTo26x() async throws {
        let (api, _) = try stubbed("26u-internal-notifications-unread-200", "26v-internal-notifications-read-200",
                                  "26w-internal-notifications-read-all-200", "26x-internal-notifications-unread-empty-200")
        let unread = try await api.inboxUnreadSummary()
        XCTAssertEqual(unread.unreadCount, 1)
        XCTAssertEqual(unread.notifications.map(\.id), [4])

        try await api.markNotificationRead(id: 4)
        try await api.markAllNotificationsRead()

        let none = try await api.inboxUnreadSummary()
        XCTAssertEqual(none, InboxUnreadSummary(notifications: [], unreadCount: 0), "26x: notifications:null")
    }
}

// MARK: - Library

final class LibraryFixtureTests: XCTestCase {
    func testLogs26y() async throws {
        let (api, _) = try stubbed("26y-logs-200")
        let page = try await api.activityLogs()
        XCTAssertEqual(page.items.map(\.type), ["twofa.disabled", "login.recovery_code", "twofa.enabled", "login"])
        XCTAssertEqual(page.meta.total, 4)
        let last = try XCTUnwrap(page.items.last)
        XCTAssertEqual(last.id, 11)
        XCTAssertEqual(last.ip, "127.0.0.1")
        XCTAssertEqual(last.deviceType, "desktop")
        XCTAssertEqual(last.osName, "Other")
        XCTAssertNotNil(last.createdAt)
    }

    func testUploads26z1To26z3() async throws {
        let (api, stub) = try stubbed("26z1-uploads-create-201", "26z2-uploads-list-200", "26z3-uploads-delete-200")
        let file = MultipartFile(filename: "tiny.png", mimeType: "image/png", data: Data(pngMagic))
        let uploaded = try await api.upload(file, as: .image)
        XCTAssertEqual(uploaded.id, 3, "keyed by upload_id")
        XCTAssertEqual(uploaded.displayName, "tiny.png")
        XCTAssertEqual(uploaded.fileExtension, "png")
        XCTAssertEqual(uploaded.size, 427)
        XCTAssertEqual(uploaded.type, "image")
        XCTAssertTrue(uploaded.isImage)
        XCTAssertNotNil(uploaded.address)
        XCTAssertTrue(stub.lastRequest?.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)

        let list = try await api.uploads()
        XCTAssertEqual(list.items, [uploaded])

        try await api.deleteUpload(id: 3)
        XCTAssertEqual(stub.lastRequest?.url?.path, "/api/v1/uploads/3")
    }

    func testData26z4To26z6() async throws {
        let (api, _) = try stubbed("26z4-data-list-200", "26z5-data-get-200", "26z6-data-delete-200")
        let list = try await api.dataRecords()
        let record = try XCTUnwrap(list.items.first)
        XCTAssertEqual(record.id, 3)
        XCTAssertEqual(record.biolinkBlockID, 9)
        XCTAssertEqual(record.linkID, 24)
        XCTAssertEqual(record.type, DataRecordKind.mail.rawValue)
        XCTAssertEqual(record.fields, [DataRecordField(key: "email", value: "grace@example.test"),
                                       DataRecordField(key: "name", value: "Grace")])

        let one = try await api.dataRecord(id: 3)
        XCTAssertEqual(one, record)
        try await api.deleteDataRecord(id: 3)
    }
}

// MARK: - Workspaces

final class WorkspaceFixtureTests: XCTestCase {
    func testMembers26z7() async throws {
        let (api, stub) = try stubbed("26z7-workspaces-members-200")
        let members = try await api.workspaceMembers(workspaceID: 234)
        XCTAssertEqual(stub.lastRequest?.url?.path, "/api/v1/workspaces/234/members")
        let owner = try XCTUnwrap(members.first)
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(owner.id, 4)
        XCTAssertEqual(owner.workspaceID, 234)
        XCTAssertEqual(owner.workspaceRole, .owner)
        XCTAssertEqual(owner.displayName, "Native Contract")
        XCTAssertTrue(owner.workspaceRole.canManageMembers)
        XCTAssertNotNil(owner.createdAt)
    }

    func testActivity26z8() async throws {
        let (api, stub) = try stubbed("26z8-workspaces-activity-200")
        let events = try await api.workspaceActivity(limit: 20)
        XCTAssertTrue(stub.lastRequest?.url?.query?.contains("limit=20") == true)
        XCTAssertEqual(events.count, 15)
        XCTAssertEqual(events.first?.action, "resource.created")
        XCTAssertEqual(events.first?.subjectType, "static")
        XCTAssertEqual(events.first?.subjectID, 29)
        XCTAssertEqual(events.filter { $0.action == "block.edited" }.count, 3)
        let joined = try XCTUnwrap(events.last)
        XCTAssertEqual(joined.action, "member.joined")
        XCTAssertNil(joined.subjectID)
        XCTAssertEqual(joined.actorName, "Native Contract")
        XCTAssertEqual(Set(events.map(\.id)).count, 15, "ids are unique")
    }

    func testCreate26z9AndScopedLists() async throws {
        let (api, stub) = try stubbed("26z9-workspaces-create-201", "26z10-links-list-other-workspace-200",
                                     "26z11-links-list-foreign-workspace")
        let workspace = try await api.createWorkspace(name: "Studio")
        XCTAssertEqual(workspace, Workspace(id: 339, name: "Studio", isPersonal: false, role: "owner", storageBytes: 0))

        await api.setWorkspace(339)
        let empty = try await api.links(page: 1)
        XCTAssertEqual(empty.items, [])
        XCTAssertEqual(stub.lastRequest?.value(forHTTPHeaderField: "X-Workspace-ID"), "339")

        await api.setWorkspace(999)
        do {
            _ = try await api.links(page: 1)
            XCTFail("expected a 403")
        } catch let error as APIError {
            XCTAssertEqual(error, .invalid("You are not a member of this workspace"), "a 403 never signs out")
        }
    }
}
