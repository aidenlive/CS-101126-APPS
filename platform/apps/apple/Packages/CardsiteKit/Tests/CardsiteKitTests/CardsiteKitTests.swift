import XCTest
@testable import CardsiteKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Fixture helpers

/// Loads `response` from a fixture captured by ContractTests/native-contract.sh,
/// plus the status it was captured with.
func fixture(_ name: String) throws -> (status: Int, body: Data) {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
                            "Missing fixture \(name).json")
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let request = try XCTUnwrap(object["_request"] as? [String: Any])
    let status = try XCTUnwrap(request["status"] as? Int)
    let response = try XCTUnwrap(object["response"])
    return (status, try JSONSerialization.data(withJSONObject: response))
}

/// Replays fixtures and records the requests the client made.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [(Int, Data, [String: String])]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [(Int, Data, [String: String])]) { self.queue = responses }

    convenience init(fixtures names: String...) throws {
        self.init(try names.map { name in
            let f = try fixture(name)
            return (f.status, f.body, [:])
        })
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next: (Int, Data, [String: String]) = try lock.withLock {
            requests.append(request)
            guard !queue.isEmpty else { throw URLError(.resourceUnavailable) }
            return queue.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: next.0, httpVersion: "HTTP/1.1", headerFields: next.2)!
        return (next.1, response)
    }

    var lastRequest: URLRequest? { lock.withLock { requests.last } }
}

let base = URL(string: "https://api.test")!

// MARK: - Decoding the live contract

final class ContractDecodingTests: XCTestCase {
    func testRegisterAndLogin() async throws {
        let stub = try StubTransport(fixtures: "01-auth-register-201", "03a-auth-login-200")
        let client = APIClient(baseURL: base, transport: stub)

        let registered = try await client.register(name: "Native Contract", email: "a@b.test", password: "password1")
        XCTAssertEqual(registered.token, "<redacted-jwt>")
        XCTAssertEqual(registered.user.name, "Native Contract")
        XCTAssertEqual(registered.user.planID, 1)
        XCTAssertNotNil(registered.user.createdAt, "timestamps with 6 fractional digits must decode")

        let outcome = try await client.signIn(email: "a@b.test", password: "password1")
        guard case .signedIn(let session) = outcome else { return XCTFail("expected signedIn") }
        XCTAssertFalse(session.token.isEmpty)
    }

    func testWrongPasswordAtSignInIsRejectedNotSessionExpired() async throws {
        let stub = try StubTransport(fixtures: "03b-auth-login-401")
        let client = APIClient(baseURL: base, transport: stub)
        do {
            _ = try await client.signIn(email: "a@b.test", password: "nope")
            XCTFail("expected throw")
        } catch let error as APIError {
            XCTAssertEqual(error, .rejected("Invalid email or password"))
        }
    }

    func testUnauthorizedOnAuthenticatedRouteExpiresSession() async throws {
        let stub = try StubTransport(fixtures: "04b-user-401")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        do {
            _ = try await client.currentUser()
            XCTFail("expected throw")
        } catch let error as APIError {
            XCTAssertEqual(error, .sessionExpired)
        }
    }

    func testLinksCreateListAndErrors() async throws {
        let stub = try StubTransport(fixtures: "06a-links-create-201", "06b-links-list-200",
                                     "06f-links-create-409-duplicate", "06g-links-create-422-plan-limit")
        let client = APIClient(baseURL: base, token: "t", transport: stub)

        let created = try await client.createLink(slug: "nc-179174903420425", destination: URL(string: "https://example.com")!)
        XCTAssertEqual(created.slug, "nc-179174903420425")
        XCTAssertEqual(created.destination, "https://example.com")
        XCTAssertTrue(created.isEnabled)
        XCTAssertFalse(created.isLapsing)
        XCTAssertNil(created.updatedAt)

        let page = try await client.links()
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.meta, PageMeta(page: 1, perPage: 25, total: 1))
        XCTAssertFalse(page.hasMore)

        do {
            _ = try await client.createLink(slug: "taken", destination: URL(string: "https://example.com")!)
            XCTFail("expected 409")
        } catch let error as APIError {
            XCTAssertEqual(error, .conflict(title: "That address is already taken", message: nil))
            XCTAssertEqual(error.localizedDescription, "That address is already taken")
        }

        do {
            _ = try await client.createLink(slug: "second", destination: URL(string: "https://example.com")!)
            XCTFail("expected 422")
        } catch let error as APIError {
            XCTAssertEqual(error, .planLimit(limit: "custom_slugs_limit", current: 1, max: 1))
        }
    }

    func testEmptyListsArriveAsNull() async throws {
        let stub = try StubTransport(fixtures: "09-biolinks-list-empty-200", "07a-statistics-overview-empty-200")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        let pages = try await client.bioPages()
        XCTAssertTrue(pages.items.isEmpty)
        XCTAssertEqual(pages.meta.total, 0)
        let traffic = try await client.dailyTraffic(linkID: 7, from: Date(), to: Date())
        XCTAssertTrue(traffic.isEmpty)
    }

    func testStatistics() async throws {
        let stub = try StubTransport(fixtures: "07b-statistics-overview-200", "07c-statistics-referrer-200", "07d-statistics-summary-200")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        let traffic = try await client.dailyTraffic(linkID: 7, from: Date(), to: Date())
        XCTAssertEqual(traffic.first?.pageviews, 1)
        XCTAssertNotNil(traffic.first?.day)
        _ = try await client.breakdown(linkID: 7, by: .referrer, from: Date(), to: Date())
        let summary = try await client.summary()
        XCTAssertGreaterThanOrEqual(summary.links, 0)
    }

    func testQRCodeImageDecodesToPNG() async throws {
        let stub = try StubTransport(fixtures: "08a-qr-codes-create-201", "08b-qr-codes-list-200")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        let qr = try await client.createQRCode(name: "Native contract QR", url: URL(string: "https://example.com")!)
        let png = try XCTUnwrap(qr.pngData)
        XCTAssertEqual(Array(png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(qr.target, "https://example.com")
        let list = try await client.qrCodes()
        XCTAssertFalse(list.items.isEmpty)
    }

    func testAccountPlanPlansWorkspacesAndUpdate() async throws {
        let stub = try StubTransport(fixtures: "10a-account-plan-200", "10b-plans-200", "05-workspaces-200", "11-account-update-200")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        let plan = try await client.accountPlan()
        XCTAssertFalse(plan.hasPaidSubscription)
        let plans = try await client.plans()
        XCTAssertEqual(plans.first?.settings?.customSlugsLimit, 1)
        XCTAssertTrue(plans.contains { $0.monthlyPrice == nil }, "Enterprise omits its price")
        let workspaces = try await client.workspaces()
        XCTAssertEqual(workspaces.first?.isPersonal, true)
        let user = try await client.updateName("New Name")
        XCTAssertFalse(user.email.isEmpty)
    }

    func testDeleteAccount() async throws {
        let stub = try StubTransport(fixtures: "13a-account-delete-401", "13c-account-delete-200")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        do {
            try await client.deleteAccount(password: "wrong")
            XCTFail("expected throw")
        } catch let error as APIError {
            guard case .rejected = error else { return XCTFail("wrong password must not end the session: \(error)") }
        }
        try await client.deleteAccount(password: "right")
        let body = try XCTUnwrap(stub.lastRequest?.httpBody)
        XCTAssertEqual(String(decoding: body, as: UTF8.self), #"{"password":"right"}"#)
    }

    func testRateLimitReadsRetryAfter() async throws {
        let f = try fixture("14-auth-login-429")
        let stub = StubTransport([(f.status, f.body, ["Retry-After": "600"])])
        let client = APIClient(baseURL: base, transport: stub)
        do {
            _ = try await client.signIn(email: "a@b.test", password: "x")
            XCTFail("expected throw")
        } catch let error as APIError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 600))
            XCTAssertTrue(error.localizedDescription.contains("10"))
        }
    }
}

// MARK: - Request shape the server requires

final class RequestShapeTests: XCTestCase {
    func testWritesCarryCSRFHeaderAndBearer() async throws {
        let stub = try StubTransport(fixtures: "06a-links-create-201")
        let client = APIClient(baseURL: base, token: "abc", transport: stub)
        await client.setWorkspace(131)
        _ = try await client.createLink(slug: "x1", destination: URL(string: "https://example.com")!)
        let request = try XCTUnwrap(stub.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.test/api/v1/links")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Requested-With"), "XMLHttpRequest")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Workspace-ID"), "131")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertEqual(String(decoding: body, as: UTF8.self),
                       #"{"location_url":"https:\/\/example.com","type":"link","url":"x1"}"#)
    }

    func testSignInSendsCSRFHeaderButNoBearer() async throws {
        let stub = try StubTransport(fixtures: "03a-auth-login-200")
        let client = APIClient(baseURL: base, token: "stale", transport: stub)
        _ = try await client.signIn(email: "a@b.test", password: "p")
        let request = try XCTUnwrap(stub.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Requested-With"), "XMLHttpRequest")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testReadsHaveNoCSRFHeaderAndUseResultsPerPage() async throws {
        let stub = try StubTransport(fixtures: "06b-links-list-200")
        let client = APIClient(baseURL: base, token: "abc", transport: stub)
        _ = try await client.links(page: 2)
        let request = try XCTUnwrap(stub.lastRequest)
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Requested-With"))
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "page", value: "2")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "results_per_page", value: String(APIClient.pageSize))))
    }

    func testAuthenticatedCallWithoutTokenFailsLocally() async throws {
        let stub = StubTransport([])
        let client = APIClient(baseURL: base, transport: stub)
        do {
            _ = try await client.currentUser()
            XCTFail("expected throw")
        } catch let error as APIError {
            XCTAssertEqual(error, .sessionExpired)
            XCTAssertTrue(stub.requests.isEmpty)
        }
    }

    func testOfflineIsClassified() {
        XCTAssertEqual(APIError.from(transportError: URLError(.notConnectedToInternet)), .offline)
        XCTAssertTrue(APIError.offline.isRetryable)
    }
}

// MARK: - Pure rules

final class RulesTests: XCTestCase {
    func testTimestampsWithAnyFraction() throws {
        let six = try XCTUnwrap(CardsiteJSON.parseTimestamp("2026-10-11T20:03:54.794461Z"))
        let five = try XCTUnwrap(CardsiteJSON.parseTimestamp("2026-10-11T20:03:54.79446Z"))
        let none = try XCTUnwrap(CardsiteJSON.parseTimestamp("2026-10-11T20:03:54Z"))
        XCTAssertEqual(six.timeIntervalSince(none), 0.794461, accuracy: 0.000_01)
        XCTAssertEqual(five.timeIntervalSince(none), 0.79446, accuracy: 0.000_01)
        XCTAssertNotNil(CardsiteJSON.parseTimestamp("2026-10-11T20:03:54.1+02:00"))
        XCTAssertNil(CardsiteJSON.parseTimestamp("yesterday"))
    }

    func testDayStrings() throws {
        let day = try XCTUnwrap(CardsiteJSON.parseDay("2026-10-11"))
        XCTAssertEqual(CardsiteJSON.dayString(day), "2026-10-11")
    }

    func testSlugRules() {
        XCTAssertNil(Slug.problem(with: "Demo-Q4-Review"))
        XCTAssertEqual(Slug.problem(with: ""), .empty)
        XCTAssertEqual(Slug.problem(with: "has space"), .invalidCharacters)
        XCTAssertEqual(Slug.problem(with: "a/b"), .invalidCharacters)
        XCTAssertEqual(Slug.problem(with: "-lead"), .mustStartAlphanumeric)
        XCTAssertEqual(Slug.problem(with: String(repeating: "a", count: 65)), .tooLong)
        XCTAssertEqual(Slug.suggestion(from: "Spring Menu 2026!"), "Spring-Menu-2026")
        XCTAssertEqual(Slug.suggestion(from: "Café  Crème"), "Cafe-Creme")
        let random = Slug.random()
        XCTAssertEqual(random.count, 7)
        XCTAssertNil(Slug.problem(with: random))
    }

    func testDestinations() {
        XCTAssertEqual(Destination.normalized("example.com/menu")?.absoluteString, "https://example.com/menu")
        XCTAssertEqual(Destination.normalized(" http://a.co ")?.absoluteString, "http://a.co")
        XCTAssertNil(Destination.normalized("javascript:alert(1)"))
        XCTAssertNil(Destination.normalized("ftp://a.co"))
        XCTAssertNil(Destination.normalized("not a url"))
        XCTAssertNil(Destination.normalized("localhost"))
    }

    func testAddresses() {
        let book = AddressBook()
        XCTAssertEqual(book.display(for: "launch"), "card.site/launch")
        XCTAssertEqual(book.cardURL(for: "launch")?.absoluteString, "https://card.site/@launch")
    }

    func testJWTExpiry() throws {
        // {"alg":"HS256","typ":"JWT"} . {"exp":1700000000} . sig
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3MDAwMDAwMDB9.c2ln"
        XCTAssertEqual(JWT.expiry(of: token), Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(JWT.isExpired(token, now: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertFalse(JWT.isExpired(token, now: Date(timeIntervalSince1970: 1_600_000_000)))
        XCTAssertFalse(JWT.isExpired("<redacted-jwt>"), "unreadable tokens are left to the server")
    }

    func testMemoryTokenStore() throws {
        let store = MemoryTokenStore()
        XCTAssertNil(store.load())
        try store.save("x")
        XCTAssertEqual(store.load(), "x")
        store.clear()
        XCTAssertNil(store.load())
    }
}
