import XCTest
@testable import CardsiteKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The existing models (Resource, QRCode, Workspace, AccountSummary,
// DailyTraffic, Session) decoded from the parity fixtures 20–26 captured by
// ContractTests/native-contract.sh. Domain models get their own tests in
// their own files.

/// `data` of a fixture, decoded the way the client decodes it.
private func payload<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    let envelope = try CardsiteJSON.decoder().decode(DataEnvelope<T>.self, from: fixture(name).body)
    return try XCTUnwrap(envelope.data, "\(name) has null data")
}

private func fixtureNames() throws -> [String] {
    let urls = try XCTUnwrap(Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures"))
    return urls.map { $0.deletingPathExtension().lastPathComponent }.sorted()
}

// MARK: - Every fixture

final class FixtureInvariantTests: XCTestCase {
    func testEveryFixtureIsAnEnvelope() throws {
        let names = try fixtureNames()
        XCTAssertGreaterThanOrEqual(names.count, 100)
        for name in names {
            let f = try fixture(name)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: f.body) as? [String: Any], name)
            if (200..<300).contains(f.status) {
                XCTAssertTrue(Set(object.keys).isSubset(of: ["data", "meta"]), "\(name): \(object.keys)")
                XCTAssertNotNil(object["data"], "\(name): success bodies always carry data (possibly null)")
                if let meta = object["meta"] as? [String: Any] {
                    XCTAssertEqual(Set(meta.keys), ["page", "per_page", "total"], name)
                }
            } else {
                XCTAssertEqual(Set(object.keys), ["error"], name)
                let error = try XCTUnwrap(object["error"] as? [String: Any], name)
                XCTAssertTrue(error["title"] is String, name)
                XCTAssertEqual(error["code"] as? Int, f.status, name)
            }
        }
    }

    func testEveryTimestampInEveryFixtureParses() throws {
        let pattern = try NSRegularExpression(pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})$")
        func visit(_ value: Any, _ name: String) {
            switch value {
            case let string as String:
                let range = NSRange(string.startIndex..., in: string)
                if pattern.firstMatch(in: string, range: range) != nil {
                    XCTAssertNotNil(CardsiteJSON.parseTimestamp(string), "\(name): \(string)")
                }
            case let array as [Any]:
                array.forEach { visit($0, name) }
            case let object as [String: Any]:
                object.values.forEach { visit($0, name) }
            default:
                break
            }
        }
        for name in try fixtureNames() {
            visit(try JSONSerialization.jsonObject(with: fixture(name).body), name)
        }
    }

    func testNoSecretsInFixtures() throws {
        for name in try fixtureNames() {
            let text = String(decoding: try fixture(name).body, as: UTF8.self)
            XCTAssertFalse(text.contains("eyJhbGci"), "\(name) holds a JWT")
            XCTAssertFalse(text.contains("cst_"), "\(name) holds an API token secret")
            XCTAssertFalse(text.contains("$2a$"), "\(name) holds a bcrypt digest")
            XCTAssertFalse(text.contains("otpauth://"), "\(name) holds a TOTP secret")
        }
    }
}

// MARK: - Resources of every type

final class ResourceFixtureTests: XCTestCase {
    func testFullyConfiguredLinkDecodes() async throws {
        let stub = try StubTransport(fixtures: "22b-links-get-full-200")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        let link = try await client.link(id: 1)
        XCTAssertEqual(link.type, LinkKind.shortLink)
        XCTAssertEqual(link.destination, "https://example.com/full")
        XCTAssertTrue(link.slug.hasPrefix("ncf-"))
        XCTAssertFalse(link.isLapsing)
        XCTAssertNotNil(link.createdAt)
    }

    func testUpdateDuplicateAndDeleteResponses() throws {
        let updated = try payload(Resource.self, "22c-links-update-full-200")
        XCTAssertEqual(updated.destination, "https://example.com/full")
        let copy = try payload(Resource.self, "22d-links-duplicate-201")
        XCTAssertTrue(copy.slug.hasSuffix("-copy"))
        XCTAssertFalse(copy.isEnabled, "a duplicate starts disabled")
        XCTAssertEqual(copy.clicks, 0)
        XCTAssertNotEqual(copy.id, updated.id)
    }

    func testEveryResourceTypeDecodesAsResource() throws {
        let cases: [(String, String, Bool)] = [
            ("24a-biolinks-create-201", "biolink", false),
            ("25a-vcards-create-201", "vcard", false),
            ("25e-events-create-201", "event", false),
            ("25i-payment-links-create-201", "payment_link", true),
            ("25m-files-create-201", "file", false),
            ("25p-static-create-201", "static", false),
        ]
        for (name, type, hasDestination) in cases {
            let resource = try payload(Resource.self, name)
            XCTAssertEqual(resource.type, type, name)
            XCTAssertEqual(resource.destination != nil, hasDestination, name)
            XCTAssertTrue(resource.isEnabled, name)
            XCTAssertFalse(resource.isLapsing, name)
        }
        XCTAssertTrue(try payload(Resource.self, "24a-biolinks-create-201").isBioPage)
    }

    func testEveryResourceListDecodesAsAPage() async throws {
        let lists: [(String, String)] = [
            ("24j-biolinks-list-200", "api/v1/biolinks"),
            ("25d-vcards-list-200", "api/v1/vcards"),
            ("25h-events-list-200", "api/v1/events"),
            ("25l-payment-links-list-200", "api/v1/payment-links"),
            ("25o-files-list-200", "api/v1/files"),
            ("25q-static-list-200", "api/v1/static"),
        ]
        for (name, path) in lists {
            let stub = try StubTransport(fixtures: name)
            let client = APIClient(baseURL: base, token: "t", transport: stub)
            let page: Page<Resource> = try await client.sendPage(path, page: 1)
            XCTAssertEqual(page.items.count, 1, name)
            XCTAssertEqual(page.meta.total, 1, name)
        }
    }

    func testRecentResourcesWithBlankLifecycleAreNotLapsing() throws {
        let recent = try payload([Resource].self, "20d-resources-recent-200")
        XCTAssertFalse(recent.isEmpty)
        XCTAssertLessThanOrEqual(recent.count, 5)
        for resource in recent {
            XCTAssertEqual(resource.lifecycleState, "", "the recent feed does not select lifecycle columns")
            XCTAssertFalse(resource.isLapsing)
            XCTAssertNotNil(resource.createdAt)
        }
    }

    func testWorkspaceScopedEmptyList() async throws {
        let stub = try StubTransport(fixtures: "26z10-links-list-other-workspace-200")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        await client.setWorkspace(42)
        let page = try await client.links()
        XCTAssertTrue(page.items.isEmpty)
        XCTAssertEqual(stub.lastRequest?.value(forHTTPHeaderField: "X-Workspace-ID"), "42")
    }

    func testMissingLinkIsInvalid() async throws {
        let stub = try StubTransport(fixtures: "22g-links-get-404")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        do {
            _ = try await client.link(id: 1)
            XCTFail("expected throw")
        } catch let error as APIError {
            XCTAssertEqual(error, .invalid("Link not found"))
        }
    }

    func testStaleBlockEditIsAConflict() async throws {
        let stub = try StubTransport(fixtures: "24e-biolink-blocks-update-409-stale")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        do {
            try await client.sendIgnoringBody(.put, "api/v1/biolink-blocks/1", body: ["version": 1])
            XCTFail("expected throw")
        } catch let error as APIError {
            guard case .conflict(let title, _) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(title.contains("reload it"), title)
        }
    }

    func testBadCheckoutURLIsInvalid() async throws {
        let stub = try StubTransport(fixtures: "25j-payment-links-create-422")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        do {
            try await client.sendIgnoringBody(.post, "api/v1/payment-links", body: ["url": "x", "location_url": "ftp://nope"])
            XCTFail("expected throw")
        } catch let error as APIError {
            XCTAssertEqual(error, .invalid("The checkout URL must start with http:// or https://"))
        }
    }
}

// MARK: - Dashboard, QR, account

final class DashboardAndAccountFixtureTests: XCTestCase {
    func testSummaryAndWorkspaceOverview() async throws {
        let stub = try StubTransport(fixtures: "20a-statistics-summary-200", "20b-statistics-all-overview-200", "20c-statistics-all-country-200")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        let summary = try await client.summary()
        XCTAssertGreaterThanOrEqual(summary.links, 1)
        let overview: [DailyTraffic]? = try await client.sendOptional(.get, "api/v1/statistics/all", query: ["type": "overview"])
        XCTAssertEqual(overview?.first?.pageviews, 1)
        XCTAssertNotNil(overview?.first?.day)
        let countries: [TrafficBreakdown]? = try await client.sendOptional(.get, "api/v1/statistics/all", query: ["type": "country_code"])
        XCTAssertNil(countries, "no breakdown rows → data:null")
    }

    func testStyledDynamicQRCode() throws {
        for name in ["23d-qr-codes-create-styled-201", "23e-qr-codes-update-200"] {
            let qr = try payload(QRCode.self, name)
            let png = try XCTUnwrap(qr.pngData, name)
            XCTAssertEqual(Array(png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], name)
            XCTAssertEqual(qr.target, "https://example.com/full", name)
        }
        XCTAssertEqual(try payload(QRCode.self, "23e-qr-codes-update-200").name, "Renamed QR")
    }

    func testTwoFactorSignIn() async throws {
        let stub = try StubTransport(fixtures: "26o-auth-login-2fa-required-200", "26p-auth-login-recovery-code-200")
        let client = APIClient(baseURL: base, transport: stub)
        let challenge = try await client.signIn(email: "a@b.test", password: "p")
        XCTAssertEqual(challenge, .twoFactorRequired)
        let outcome = try await client.signIn(email: "a@b.test", password: "p", recoveryCode: "abcd-efgh-ijkl-mnop")
        guard case .signedIn(let session) = outcome else { return XCTFail("expected signedIn") }
        XCTAssertEqual(session.recoveryCodesRemaining, 9)
        XCTAssertEqual(session.user.planID, 6, "the PARITY run is on Enterprise")
        let body = String(decoding: try XCTUnwrap(stub.lastRequest?.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("\"recovery_code\":\"abcd-efgh-ijkl-mnop\""), body)
    }

    func testWrongCodeAndPasswordAreRejectedNotSignedOut() async throws {
        let stub = try StubTransport(fixtures: "26l-2fa-verify-bad-code", "26q-2fa-disable-401")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        do {
            try await client.sendIgnoringBody(.post, "api/v1/auth/2fa/verify", body: ["code": "000000"], credentialCheck: true)
            XCTFail("expected throw")
        } catch let error as APIError {
            XCTAssertEqual(error, .rejected("Invalid 2FA code"))
        }
        do {
            try await client.sendIgnoringBody(.delete, "api/v1/auth/2fa", body: ["password": "nope"], credentialCheck: true)
            XCTFail("expected throw")
        } catch let error as APIError {
            XCTAssertEqual(error, .rejected("Invalid password"))
        }
    }

    func testCreatedWorkspaceAndMembers() throws {
        let workspace = try payload(Workspace.self, "26z9-workspaces-create-201")
        XCTAssertEqual(workspace.name, "Studio")
        XCTAssertFalse(workspace.isPersonal)
        XCTAssertEqual(workspace.role, "owner")
        XCTAssertEqual(workspace.storageBytes, 0)
    }

    func testMessageBodiesDecodeAsJSONValue() throws {
        for name in ["22f-links-delete-200", "24f-biolink-blocks-order-200", "26f-account-tokens-revoke-200",
                     "26i-account-password-200", "26r-2fa-disable-200", "26z3-uploads-delete-200", "26z6-data-delete-200"] {
            let body = try payload(JSONValue.self, name)
            XCTAssertNotNil(body["message"]?.stringValue, name)
        }
    }
}
