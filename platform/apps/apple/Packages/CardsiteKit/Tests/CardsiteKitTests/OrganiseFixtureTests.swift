import XCTest
@testable import CardsiteKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Projects, custom domains, pixels and plan capabilities: fixtures 21a–21h,
// 10a and 10b, plus hand-built bodies for the answers the contract run
// could not capture (a verified domain, the 422 and 503 from verify).

private func stubbed(_ fixtures: String...) throws -> (APIClient, StubTransport) {
    let stub = StubTransport(try fixtures.map { name in
        let f = try fixture(name)
        return (f.status, f.body, [:])
    })
    return (APIClient(baseURL: base, token: "t", transport: stub), stub)
}

private func body(of request: URLRequest?) throws -> JSONValue {
    try CardsiteJSON.decoder().decode(JSONValue.self, from: XCTUnwrap(request?.httpBody))
}

private func json(_ text: String) -> Data { Data(text.utf8) }

// MARK: - Projects

final class ProjectTests: XCTestCase {
    func testCreateUpdateList21aTo21c() async throws {
        let (api, stub) = try stubbed("21a-projects-create-201", "21b-projects-update-200", "21c-projects-list-200")

        let created = try await api.createProject(ProjectInput(name: "  Launch ", color: "#3366ff"))
        XCTAssertEqual(created, Project(id: 3, workspaceID: 234, name: "Launch", color: "#3366ff",
                                        createdAt: created.createdAt, updatedAt: nil))
        XCTAssertNotNil(created.createdAt)
        XCTAssertEqual(stub.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(stub.lastRequest?.url?.path, "/api/v1/projects")
        XCTAssertEqual(stub.lastRequest?.value(forHTTPHeaderField: "X-Requested-With"), "XMLHttpRequest")
        XCTAssertEqual(try body(of: stub.lastRequest), ["name": "Launch", "color": "#3366ff"], "the name is trimmed")

        let renamed = try await api.updateProject(id: 3, ProjectInput(name: "Launch week", color: "#3366ff"))
        XCTAssertEqual(renamed.name, "Launch week")
        XCTAssertEqual(stub.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(stub.lastRequest?.url?.path, "/api/v1/projects/3")

        let page = try await api.projects()
        XCTAssertEqual(page.items.map(\.name), ["Launch week"])
        XCTAssertNotNil(page.items.first?.updatedAt)
        XCTAssertEqual(page.meta.total, 1)
        XCTAssertFalse(page.hasMore)
        XCTAssertEqual(page.items.first?.option, ProjectOption(id: 3, name: "Launch week", color: "#3366ff"))
    }

    func testDeleteAndMissingColour() async throws {
        let stub = StubTransport([
            (200, json(#"{"data":{"message":"Project deleted"}}"#), [:]),
            (200, json(#"{"data":[{"id":9,"name":"Plain","color":""}],"meta":{"page":1,"per_page":50,"total":1}}"#), [:]),
        ])
        let api = APIClient(baseURL: base, token: "t", transport: stub)
        try await api.deleteProject(id: 3)
        XCTAssertEqual(stub.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(stub.lastRequest?.url?.path, "/api/v1/projects/3")

        let page = try await api.projects()
        let plain = try XCTUnwrap(page.items.first)
        XCTAssertEqual(plain.color, "")
        XCTAssertNil(plain.option.color, "an unset colour is no colour in pickers")
    }
}

// MARK: - Custom domains

final class CustomDomainTests: XCTestCase {
    func testCreateAndList21dAnd21e() async throws {
        let (api, stub) = try stubbed("21d-domains-create-201", "21e-domains-list-200")
        let input = CustomDomainInput(host: " HTTPS://NC-179177059010024.example.test/path ")
        XCTAssertEqual(input.normalizedHost, "nc-179177059010024.example.test")
        XCTAssertTrue(input.hasValidHost)

        let domain = try await api.createCustomDomain(input)
        XCTAssertEqual(domain.id, 3)
        XCTAssertEqual(domain.scheme, "https://", "stored as the contract run sent it")
        XCTAssertEqual(domain.bareScheme, "https")
        XCTAssertEqual(domain.address, "https://nc-179177059010024.example.test")
        XCTAssertEqual(domain.kind, .custom)
        XCTAssertEqual(domain.redirect, .permanent)
        XCTAssertEqual(domain.customIndexURL, "", "omitempty: absent decodes as empty")
        XCTAssertEqual(domain.customNotFoundURL, "")
        XCTAssertTrue(domain.isEnabled)
        XCTAssertFalse(domain.sslIsEnabled)
        XCTAssertFalse(domain.forceSSL)
        XCTAssertFalse(domain.forwardParameters)
        XCTAssertFalse(domain.isVerified)
        XCTAssertNil(domain.lastVerifiedAt)
        XCTAssertNil(domain.linkID)
        XCTAssertEqual(domain.option, DomainOption(id: 3, scheme: "https://", host: "nc-179177059010024.example.test",
                                                   isEnabled: true, isVerified: false))

        let sent = try body(of: stub.lastRequest)
        XCTAssertEqual(sent, [
            "host": "nc-179177059010024.example.test",
            "scheme": "https",
            "type": 0,
            "redirect_type": "301",
            "custom_index_url": "",
            "custom_not_found_url": "",
            "ssl_is_enabled": false,
            "force_ssl": false,
            "forward_parameters": false,
        ])

        let page = try await api.customDomains()
        XCTAssertEqual(page.items, [domain])
    }

    func testUpdateSendsOnlyWhatChanged() throws {
        let stored = try CardsiteJSON.decoder().decode(DataEnvelope<CustomDomain>.self,
                                                       from: fixture("21d-domains-create-201").body).data
        let domain = try XCTUnwrap(stored)
        var input = CustomDomainInput(domain)
        XCTAssertEqual(input.scheme, "https")
        XCTAssertEqual(input.updateBody(from: domain), [:], "`https://` and `https` are the same scheme")

        input.redirectType = .frame
        input.customNotFoundURL = " https://example.com/404 "
        XCTAssertEqual(input.updateBody(from: domain), [
            "redirect_type": "frame",
            "custom_not_found_url": "https://example.com/404",
        ])

        input.forceSSL = true
        XCTAssertNil(input.updateBody(from: domain)["force_ssl"], "force SSL means nothing without SSL")
        input.sslIsEnabled = true
        XCTAssertEqual(input.updateBody(from: domain)["force_ssl"], true)
        XCTAssertEqual(input.updateBody(from: domain)["ssl_is_enabled"], true)
    }

    func testUnchangedUpdateSendsNothing() async throws {
        let stub = StubTransport([])
        let api = APIClient(baseURL: base, token: "t", transport: stub)
        let domain = CustomDomain(id: 4, scheme: "https://", host: "go.example.com")
        let saved = try await api.updateCustomDomain(domain, to: CustomDomainInput(domain))
        XCTAssertEqual(saved, domain)
        XCTAssertTrue(stub.requests.isEmpty)
    }

    func testHostValidation() {
        XCTAssertTrue(CustomDomainInput(host: "links.example.co.uk").hasValidHost)
        XCTAssertTrue(CustomDomainInput(host: "xn--bcher-kva.example").hasValidHost)
        XCTAssertFalse(CustomDomainInput(host: "localhost").hasValidHost)
        XCTAssertFalse(CustomDomainInput(host: "bad host.example").hasValidHost)
        XCTAssertFalse(CustomDomainInput(host: "-x.example").hasValidHost)
        XCTAssertFalse(CustomDomainInput(host: "example..com").hasValidHost)
        XCTAssertFalse(CustomDomainInput(host: "").hasValidHost)
    }

    private let domainJSON = #"{"id":4,"workspace_id":234,"scheme":"https","host":"go.example.com","type":0,"is_enabled":true,"ssl_is_enabled":true,"force_ssl":true,"redirect_type":"301","forward_parameters":false,"is_verified":VERIFIED,"last_verified_at":"2026-10-12T02:03:12.104679Z","created_at":"2026-10-12T02:03:12.104679Z","updated_at":null}"#

    func testVerifyOutcomes() async throws {
        let verified = domainJSON.replacingOccurrences(of: "VERIFIED", with: "true")
        let pending = domainJSON.replacingOccurrences(of: "VERIFIED", with: "false")
        let stub = StubTransport([
            (200, json(#"{"data":\#(verified)}"#), [:]),
            (422, json(#"{"data":\#(pending),"error":{"title":"go.example.com does not point at this deployment yet","message":"Point go.example.com at card.site, then verify again. DNS changes can take a while to propagate.","code":422}}"#), [:]),
            (503, json(#"{"error":{"title":"Domain verification is not configured on this deployment","code":503}}"#), [:]),
            (404, json(#"{"error":{"title":"Domain not found","code":404}}"#), [:]),
        ])
        let api = APIClient(baseURL: base, token: "t", transport: stub)

        guard case .verified(let domain) = try await api.verifyCustomDomain(id: 4) else { return XCTFail("expected verified") }
        XCTAssertTrue(domain.isVerified)
        XCTAssertNotNil(domain.lastVerifiedAt)
        XCTAssertEqual(stub.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(stub.lastRequest?.url?.path, "/api/v1/domains/4/verify")
        XCTAssertEqual(stub.lastRequest?.value(forHTTPHeaderField: "X-Requested-With"), "XMLHttpRequest")

        let notYet = try await api.verifyCustomDomain(id: 4)
        guard case .notVerified(let row, let title, let message) = notYet else { return XCTFail("\(notYet)") }
        XCTAssertEqual(row?.isVerified, false)
        XCTAssertEqual(title, "go.example.com does not point at this deployment yet")
        XCTAssertEqual(message, "Point go.example.com at card.site, then verify again. DNS changes can take a while to propagate.")

        let unavailable = try await api.verifyCustomDomain(id: 4)
        XCTAssertEqual(unavailable, .unavailable("Domain verification is not configured on this deployment"),
                       "a 503 here is not maintenance")

        do {
            _ = try await api.verifyCustomDomain(id: 4)
            XCTFail("expected a 404")
        } catch let error as APIError {
            XCTAssertEqual(error, .invalid("Domain not found"))
        }
    }

    func testVerifyWithExpiredSessionStillSignsOut() async throws {
        let stub = StubTransport([(401, json(#"{"error":{"title":"Unauthorized","code":401}}"#), [:])])
        let api = APIClient(baseURL: base, token: "t", transport: stub)
        do {
            _ = try await api.verifyCustomDomain(id: 4)
            XCTFail("expected a throw")
        } catch let error as APIError {
            XCTAssertEqual(error, .sessionExpired)
        }
    }
}

// MARK: - Live edits, verify and deletes (21l–21r)

final class OrganiseEditFixtureTests: XCTestCase {
    func testDomainUpdate21l() async throws {
        let (api, stub) = try stubbed("21l-domains-update-200")
        let original = CustomDomain(id: 5, workspaceID: 484, scheme: "https://", host: "nc-179177469018122.example.test")
        var input = CustomDomainInput(original)
        input.redirectType = .frame
        input.customNotFoundURL = "https://example.com/404"
        input.sslIsEnabled = true
        input.forceSSL = true

        let saved = try await api.updateCustomDomain(original, to: input)
        XCTAssertEqual(stub.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(stub.lastRequest?.url?.path, "/api/v1/domains/5")
        XCTAssertEqual(try body(of: stub.lastRequest), [
            "redirect_type": "frame",
            "custom_not_found_url": "https://example.com/404",
            "ssl_is_enabled": true,
            "force_ssl": true,
        ], "only what changed")

        XCTAssertEqual(saved.scheme, "https", "the contract run sent the bare scheme")
        XCTAssertEqual(saved.address, "https://nc-179177469018122.example.test")
        XCTAssertEqual(saved.redirect, .frame)
        XCTAssertEqual(saved.customNotFoundURL, "https://example.com/404")
        XCTAssertEqual(saved.customIndexURL, "", "left out by omitempty")
        XCTAssertTrue(saved.sslIsEnabled)
        XCTAssertTrue(saved.forceSSL)
        XCTAssertFalse(saved.isVerified)
        XCTAssertEqual(CustomDomainInput(saved).updateBody(from: saved), [:])
    }

    func testVerify21mIsNotVerifiedWithTheServersAdvice() async throws {
        let (api, _) = try stubbed("21m-domains-verify-422")
        let outcome = try await api.verifyCustomDomain(id: 5)
        guard case .notVerified(let domain, let title, let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(domain?.id, 5)
        XCTAssertEqual(domain?.isVerified, false)
        XCTAssertEqual(title, "nc-179177469018122.example.test does not point at this deployment yet")
        XCTAssertEqual(message, "Point nc-179177469018122.example.test at localhost, then verify again. DNS changes can take a while to propagate.")
    }

    func testPixelUpdate21nAndProjectRecolour21o() async throws {
        let (api, stub) = try stubbed("21n-pixels-update-200", "21o-projects-recolour-200")
        let pixel = try await api.updatePixel(id: 5, PixelInput(name: "Ads", type: "linkedin", pixel: "0987654321"))
        XCTAssertEqual(pixel.type, "linkedin")
        XCTAssertEqual(pixel.pixel, "0987654321")
        XCTAssertEqual(pixel.name, "Ads")

        let project = try await api.updateProject(id: 5, ProjectInput(name: "Launch week", color: "#22aa66"))
        XCTAssertEqual(project.color, "#22aa66")
        XCTAssertEqual(project.name, "Launch week")
        XCTAssertEqual(try body(of: stub.lastRequest), ["name": "Launch week", "color": "#22aa66"])
    }

    func testDeletes21pTo21r() async throws {
        let (api, stub) = try stubbed("21p-pixels-delete-200", "21q-domains-delete-200", "21r-projects-delete-200")
        try await api.deletePixel(id: 5)
        XCTAssertEqual(stub.lastRequest?.url?.path, "/api/v1/pixels/5")
        try await api.deleteCustomDomain(id: 5)
        XCTAssertEqual(stub.lastRequest?.url?.path, "/api/v1/domains/5")
        try await api.deleteProject(id: 5)
        XCTAssertEqual(stub.lastRequest?.url?.path, "/api/v1/projects/5")
        XCTAssertTrue(stub.requests.allSatisfy { $0.httpMethod == "DELETE" })
    }
}

// MARK: - Pixels

final class PixelTests: XCTestCase {
    func testTypes21f() async throws {
        let (api, _) = try stubbed("21f-pixels-types-200")
        let types = try await api.pixelTypes()
        XCTAssertEqual(types.count, 24)
        XCTAssertEqual(types.first, PixelType(key: "facebook", name: "Facebook Pixel", description: "Meta Ads conversion tracking",
                                              fieldLabel: "Pixel ID", emitsBeacon: true))
        XCTAssertEqual(types.filter(\.emitsBeacon).map(\.key), ["facebook", "linkedin", "pinterest", "quora"])
        XCTAssertEqual(types.first { $0.key == "google_tag_manager" }?.fieldLabel, "Container ID")
        XCTAssertEqual(Set(types.map(\.key)).count, 24)
    }

    func testCreateList21gAnd21h() async throws {
        let (api, stub) = try stubbed("21g-pixels-create-201", "21h-pixels-list-200")
        let created = try await api.createPixel(PixelInput(name: "Ads ", type: "facebook", pixel: " 1234567890"))
        XCTAssertEqual(created.id, 3)
        XCTAssertEqual(created.type, "facebook")
        XCTAssertEqual(created.name, "Ads")
        XCTAssertEqual(created.pixel, "1234567890")
        XCTAssertEqual(created.workspaceID, 234)
        XCTAssertNil(created.updatedAt)
        XCTAssertEqual(try body(of: stub.lastRequest), ["name": "Ads", "type": "facebook", "pixel": "1234567890"])

        let page = try await api.pixels()
        XCTAssertEqual(page.items, [created])
        XCTAssertEqual(PixelInput(created), PixelInput(name: "Ads", type: "facebook", pixel: "1234567890"))
    }

    func testUpdateAndDelete() async throws {
        let stub = StubTransport([
            (200, json(#"{"data":{"id":3,"type":"linkedin","name":"Ads","pixel":"777"}}"#), [:]),
            (200, json(#"{"data":{"message":"Pixel deleted"}}"#), [:]),
        ])
        let api = APIClient(baseURL: base, token: "t", transport: stub)
        let updated = try await api.updatePixel(id: 3, PixelInput(name: "Ads", type: "linkedin", pixel: "777"))
        XCTAssertEqual(updated.type, "linkedin")
        XCTAssertEqual(stub.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(stub.lastRequest?.url?.path, "/api/v1/pixels/3")
        try await api.deletePixel(id: 3)
        XCTAssertEqual(stub.lastRequest?.httpMethod, "DELETE")
    }

    func testFallbackName() {
        XCTAssertEqual(PixelType.fallbackName(for: "google_tag_manager"), "Google Tag Manager")
        XCTAssertEqual(PixelType.fallbackName(for: "x"), "X")
    }
}

// MARK: - Plan capabilities

final class PlanCapabilityTests: XCTestCase {
    func testFreeAccountUsesThePlanDefaults10aAnd10b() async throws {
        let (api, stub) = try stubbed("10a-account-plan-200", "10b-plans-200")
        let capabilities = try await api.planCapabilities()
        XCTAssertEqual(stub.requests.map { $0.url?.path }, ["/api/v1/account/plan", "/api/v1/plans"])
        XCTAssertEqual(capabilities.settings["custom_slugs_limit"], 1, "plan 1 (Free)")
        XCTAssertEqual(capabilities.settings["domains_limit"], 0)
        XCTAssertTrue(capabilities.targeting)
        XCTAssertTrue(capabilities.passwordProtection)
        XCTAssertTrue(capabilities.includes("premium_blocks"))
    }

    func testOverrideWinsKeyByKey() throws {
        let plans = try XCTUnwrap(try CardsiteJSON.decoder().decode(DataEnvelope<[JSONValue]>.self,
                                                                  from: fixture("10b-plans-200").body).data)
        let merged = PlanCapabilities.effective(plans: plans, planID: 3, override: [
            "targeting_is_enabled": false,
            "custom_slugs_limit": 50,
        ])
        XCTAssertFalse(merged.targeting, "the override switches a default off")
        XCTAssertEqual(merged.settings["custom_slugs_limit"], 50)
        XCTAssertEqual(merged.settings["domains_limit"], 1, "Pro's own value survives where the override is silent")
        XCTAssertTrue(merged.passwordProtection)
    }

    func testDefaultPlanWhenNoneMatches() {
        let plans: [JSONValue] = [
            ["id": 1, "settings": ["ai_tools": false]],
            ["id": 2, "is_default": true, "settings": ["ai_tools": true, "targeting_is_enabled": true]],
        ]
        XCTAssertTrue(PlanCapabilities.effective(plans: plans, planID: 99, override: [:]).includes("ai_tools"))
        XCTAssertTrue(PlanCapabilities.effective(plans: plans, planID: nil, override: [:]).targeting)
        XCTAssertFalse(PlanCapabilities.effective(plans: plans, planID: 1, override: [:]).includes("ai_tools"))
        XCTAssertEqual(PlanCapabilities.effective(plans: [], planID: 1, override: ["ai_tools": true]).settings,
                       ["ai_tools": true], "an override alone still counts")
        XCTAssertFalse(PlanCapabilities.effective(plans: [], planID: 1, override: [:]).targeting,
                       "a key nobody grants is withheld")
    }
}
