import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends requests. URLSession in the app, a closure in tests.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

/// The Cardsite REST API, v1 (platform/shared/contracts/openapi.yaml), as
/// observed live by ContractTests/native-contract.sh.
///
/// Rules the server enforces that this client handles for every caller:
/// - `Authorization: Bearer <JWT>` on authenticated routes. There is no
///   refresh token and no logout endpoint; the JWT lasts 7 days.
/// - `X-Requested-With: XMLHttpRequest` on every write, sign-in included,
///   or the server answers 403 "CSRF check failed".
/// - `X-Workspace-ID` selects a workspace; without it the personal one is used.
public actor APIClient {
    public let baseURL: URL
    private let transport: HTTPTransport
    private let decoder = CardsiteJSON.decoder()
    private let encoder = CardsiteJSON.encoder()
    private let userAgent: String

    public private(set) var token: String?
    public private(set) var workspaceID: Int?

    public init(baseURL: URL, token: String? = nil, transport: HTTPTransport = URLSessionTransport(), userAgent: String = "Cardsite-Apple") {
        self.baseURL = baseURL
        self.token = token
        self.transport = transport
        self.userAgent = userAgent
    }

    public func setToken(_ token: String?) { self.token = token }
    public func setWorkspace(_ id: Int?) { self.workspaceID = id }

    // MARK: Auth

    public func register(name: String, email: String, password: String) async throws -> Session {
        let payload: AuthPayload = try await send(
            .post, "api/v1/auth/register",
            body: ["name": name, "email": email, "password": password],
            authenticated: false
        )
        return try session(from: payload)
    }

    /// Pass `twoFactorCode` or `recoveryCode` on the second attempt after
    /// ``SignInOutcome/twoFactorRequired``.
    public func signIn(email: String, password: String, twoFactorCode: String? = nil, recoveryCode: String? = nil) async throws -> SignInOutcome {
        var body = ["email": email, "password": password]
        if let twoFactorCode { body["twofa_token"] = twoFactorCode }
        if let recoveryCode { body["recovery_code"] = recoveryCode }
        let payload: AuthPayload = try await send(.post, "api/v1/auth/login", body: body, authenticated: false, credentialCheck: true)
        if payload.twofaRequired == true, payload.token == nil {
            return .twoFactorRequired
        }
        return .signedIn(try session(from: payload))
    }

    /// Always succeeds for a well-formed email, whether or not an account exists.
    public func requestPasswordReset(email: String) async throws {
        try await sendIgnoringBody(.post, "api/v1/auth/lost-password", body: ["email": email], authenticated: false)
    }

    private func session(from payload: AuthPayload) throws -> Session {
        guard let token = payload.token, let user = payload.user else {
            throw APIError.decoding("Sign-in response had no token or user")
        }
        return Session(token: token, user: user, recoveryCodesRemaining: payload.recoveryCodesRemaining)
    }

    // MARK: Account

    /// Note: the server caches `GET /user` for ~10 minutes and does not clear
    /// it on `PUT /account`, so after an update keep the returned user.
    public func currentUser() async throws -> User {
        try await send(.get, "api/v1/user")
    }

    public func updateName(_ name: String) async throws -> User {
        try await send(.put, "api/v1/account", body: ["name": name])
    }

    /// Permanently deletes the account. The server cancels a paid
    /// subscription first and refuses (409 `active_subscription`) if it can't.
    public func deleteAccount(password: String) async throws {
        try await sendIgnoringBody(.delete, "api/v1/account", body: ["password": password], credentialCheck: true)
    }

    public func workspaces() async throws -> [Workspace] {
        let list: [Workspace]? = try await sendOptional(.get, "api/v1/workspaces")
        return list ?? []
    }

    public func accountPlan() async throws -> AccountPlan {
        try await send(.get, "api/v1/account/plan")
    }

    public func plans() async throws -> [Plan] {
        let list: [Plan]? = try await sendOptional(.get, "api/v1/plans")
        return list ?? []
    }

    public func summary() async throws -> AccountSummary {
        try await send(.get, "api/v1/statistics")
    }

    // MARK: Links

    public static let pageSize = 50

    public func links(page: Int = 1) async throws -> Page<Resource> {
        try await sendPage("api/v1/links", page: page)
    }

    public func bioPages(page: Int = 1) async throws -> Page<Resource> {
        try await sendPage("api/v1/biolinks", page: page)
    }

    public func link(id: Int) async throws -> Resource {
        try await send(.get, "api/v1/links/\(id)")
    }

    public func createLink(slug: String, destination: URL) async throws -> Resource {
        try await send(.post, "api/v1/links", body: [
            "type": LinkKind.shortLink,
            "url": slug,
            "location_url": destination.absoluteString,
        ])
    }

    /// Updates then re-reads: the PUT response carries the pre-write timestamps.
    public func updateLink(id: Int, destination: URL? = nil, isEnabled: Bool? = nil) async throws -> Resource {
        var body: [String: JSONValue] = [:]
        if let destination { body["location_url"] = .string(destination.absoluteString) }
        if let isEnabled { body["is_enabled"] = .bool(isEnabled) }
        let _: Resource = try await send(.put, "api/v1/links/\(id)", body: body)
        return try await link(id: id)
    }

    public func deleteLink(id: Int) async throws {
        try await sendIgnoringBody(.delete, "api/v1/links/\(id)")
    }

    // MARK: Statistics

    public func dailyTraffic(linkID: Int, from: Date, to: Date) async throws -> [DailyTraffic] {
        let list: [DailyTraffic]? = try await sendOptional(.get, "api/v1/statistics/\(linkID)", query: [
            "type": "overview",
            "start_date": CardsiteJSON.dayString(from),
            "end_date": CardsiteJSON.dayString(to),
        ])
        return list ?? []
    }

    public func breakdown(linkID: Int, by dimension: BreakdownDimension, from: Date, to: Date) async throws -> [TrafficBreakdown] {
        let list: [TrafficBreakdown]? = try await sendOptional(.get, "api/v1/statistics/\(linkID)", query: [
            "type": dimension.rawValue,
            "start_date": CardsiteJSON.dayString(from),
            "end_date": CardsiteJSON.dayString(to),
        ])
        return list ?? []
    }

    // MARK: QR codes

    public func qrCodes(page: Int = 1) async throws -> Page<QRCode> {
        try await sendPage("api/v1/qr-codes", page: page)
    }

    /// - Parameter linkID: the short link the code encodes, when it encodes
    ///   one. Pointing a QR code at a short link makes it dynamic: changing
    ///   the link's destination later changes where every printed copy goes.
    public func createQRCode(name: String, url: URL, linkID: Int? = nil) async throws -> QRCode {
        var body: [String: JSONValue] = [
            "name": .string(name),
            "type": .string("url"),
            "settings": .object(["url": .string(url.absoluteString)]),
        ]
        if let linkID { body["link_id"] = .int(linkID) }
        return try await send(.post, "api/v1/qr-codes", body: body)
    }

    public func deleteQRCode(id: Int) async throws {
        try await sendIgnoringBody(.delete, "api/v1/qr-codes/\(id)")
    }

    // MARK: Transport

    public enum Method: String, Sendable { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }

    func makeRequest(_ method: Method, _ path: String, query: [String: String] = [:], body: Data?, authenticated: Bool) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.transport("Bad URL for \(path)")
        }
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.transport("Bad URL for \(path)") }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if method != .get {
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated {
            guard let token else { throw APIError.sessionExpired }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let workspaceID {
                request.setValue(String(workspaceID), forHTTPHeaderField: "X-Workspace-ID")
            }
        }
        return request
    }

    private func perform(_ method: Method, _ path: String, query: [String: String] = [:], body: (any Encodable)?, authenticated: Bool, credentialCheck: Bool) async throws -> Data {
        let encoded = try body.map { try encoder.encode($0) }
        let request = try makeRequest(method, path, query: query, body: encoded, authenticated: authenticated)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.from(transportError: error)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.from(status: response.statusCode, body: data, headers: response.allHeaderFields, credentialCheck: credentialCheck)
        }
        return data
    }

    private func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> DataEnvelope<T> {
        do {
            return try decoder.decode(DataEnvelope<T>.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    func send<T: Decodable>(_ method: Method, _ path: String, query: [String: String] = [:], body: (any Encodable)? = nil, authenticated: Bool = true, credentialCheck: Bool = false) async throws -> T {
        let data = try await perform(method, path, query: query, body: body, authenticated: authenticated, credentialCheck: credentialCheck)
        guard let value = try decodeEnvelope(T.self, from: data).data else {
            throw APIError.decoding("Empty data for \(path)")
        }
        return value
    }

    func sendOptional<T: Decodable>(_ method: Method, _ path: String, query: [String: String] = [:]) async throws -> T? {
        let data = try await perform(method, path, query: query, body: nil, authenticated: true, credentialCheck: false)
        return try decodeEnvelope(T.self, from: data).data
    }

    func sendPage<T: Decodable & Sendable>(_ path: String, page: Int) async throws -> Page<T> {
        let query = ["page": String(page), "results_per_page": String(Self.pageSize)]
        let data = try await perform(.get, path, query: query, body: nil, authenticated: true, credentialCheck: false)
        let envelope = try decodeEnvelope([T].self, from: data)
        let items = envelope.data ?? []
        let meta = envelope.meta ?? PageMeta(page: page, perPage: Self.pageSize, total: items.count)
        return Page(items: items, meta: meta)
    }

    func sendIgnoringBody(_ method: Method, _ path: String, body: (any Encodable)? = nil, authenticated: Bool = true, credentialCheck: Bool = false) async throws {
        _ = try await perform(method, path, body: body, authenticated: authenticated, credentialCheck: credentialCheck)
    }
}

/// A small JSON value for request bodies with mixed types.
public enum JSONValue: Encodable, Sendable, Equatable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case object([String: JSONValue])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}
