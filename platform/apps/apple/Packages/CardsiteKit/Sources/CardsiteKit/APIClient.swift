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
    //
    // Domain files (`APIClient+<Domain>.swift`) build on these internal
    // helpers. Every request made through them carries `Accept`, `User-Agent`
    // and, on every write, `X-Requested-With`. Authenticated requests also
    // carry the bearer token and the current `X-Workspace-ID`. Both are read
    // when the request is built, so `setToken` and `setWorkspace` apply from
    // the next request on.

    public enum Method: String, Sendable {
        case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
    }

    func makeRequest(_ method: Method, _ path: String, query: [String: String] = [:], body: Data?,
                     contentType: String = "application/json", accept: String = "application/json",
                     authenticated: Bool) throws -> URLRequest {
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
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if method != .get {
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        }
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
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

    /// Sends a built request and returns the body of a 2xx response.
    /// Anything else becomes an ``APIError``.
    func execute(_ request: URLRequest, credentialCheck: Bool = false) async throws -> Data {
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

    /// Encodes `body` as JSON, sends the request and returns the raw body.
    func perform(_ method: Method, _ path: String, query: [String: String] = [:], body: (any Encodable)?, authenticated: Bool, credentialCheck: Bool) async throws -> Data {
        let encoded = try body.map { try encoder.encode($0) }
        let request = try makeRequest(method, path, query: query, body: encoded, authenticated: authenticated)
        return try await execute(request, credentialCheck: credentialCheck)
    }

    /// Decodes `{data, meta}`. `data` is nil when the server sent `null`
    /// (an empty list) or left it out.
    func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> DataEnvelope<T> {
        do {
            return try decoder.decode(DataEnvelope<T>.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// JSON in, `data` out. Throws ``APIError/decoding(_:)`` when `data` is null.
    func send<T: Decodable>(_ method: Method, _ path: String, query: [String: String] = [:], body: (any Encodable)? = nil, authenticated: Bool = true, credentialCheck: Bool = false) async throws -> T {
        let data = try await perform(method, path, query: query, body: body, authenticated: authenticated, credentialCheck: credentialCheck)
        guard let value = try decodeEnvelope(T.self, from: data).data else {
            throw APIError.decoding("Empty data for \(path)")
        }
        return value
    }

    /// Like ``send(_:_:query:body:authenticated:credentialCheck:)`` but a null
    /// `data` is nil. Use it for unpaginated lists (`[T]?`, nil means empty).
    func sendOptional<T: Decodable>(_ method: Method, _ path: String, query: [String: String] = [:], body: (any Encodable)? = nil) async throws -> T? {
        let data = try await perform(method, path, query: query, body: body, authenticated: true, credentialCheck: false)
        return try decodeEnvelope(T.self, from: data).data
    }

    /// One page of a paginated list.
    ///
    /// The server reads the page size under two names: most lists use
    /// `results_per_page`, while `/logs`, `/internal-notifications`, `/pwas`
    /// and `/payments` use `per_page`. Both are sent with the same value, so
    /// every list honours ``pageSize``. Pass either key in `query` to change
    /// the size; extra keys (`search`, `type`, `link_id`, …) pass through.
    /// The response meta is always `{page, per_page, total}`.
    func sendPage<T: Decodable & Sendable>(_ path: String, page: Int, query: [String: String] = [:]) async throws -> Page<T> {
        let size = query["results_per_page"] ?? query["per_page"] ?? String(Self.pageSize)
        var merged = query
        merged["page"] = String(page)
        merged["results_per_page"] = size
        merged["per_page"] = size
        let data = try await perform(.get, path, query: merged, body: nil, authenticated: true, credentialCheck: false)
        let envelope = try decodeEnvelope([T].self, from: data)
        let items = envelope.data ?? []
        let meta = envelope.meta ?? PageMeta(page: page, perPage: Int(size) ?? Self.pageSize, total: items.count)
        return Page(items: items, meta: meta)
    }

    func sendIgnoringBody(_ method: Method, _ path: String, query: [String: String] = [:], body: (any Encodable)? = nil, authenticated: Bool = true, credentialCheck: Bool = false) async throws {
        _ = try await perform(method, path, query: query, body: body, authenticated: authenticated, credentialCheck: credentialCheck)
    }

    /// `multipart/form-data` upload (file links, static sites, uploads). The
    /// response is the usual JSON envelope. Fields are sent in key order,
    /// then the files in the order given.
    ///
    /// The method has no default value here: the `sendMultipart(path, …)`
    /// overload below is the POST shorthand, and a leading unlabeled default
    /// would make the two overloads compete.
    func sendMultipart<T: Decodable>(_ method: Method, _ path: String, fields: [String: String], files: [MultipartFile]) async throws -> T {
        let boundary = "CardsiteBoundary-\(UUID().uuidString)"
        let body = MultipartFile.formBody(boundary: boundary, fields: fields, files: files)
        let request = try makeRequest(method, path, body: body, contentType: "multipart/form-data; boundary=\(boundary)", authenticated: true)
        let data = try await execute(request)
        guard let value = try decodeEnvelope(T.self, from: data).data else {
            throw APIError.decoding("Empty data for \(path)")
        }
        return value
    }

    /// `sendMultipart(.post, path, …)`.
    func sendMultipart<T: Decodable>(_ path: String, fields: [String: String], files: [MultipartFile]) async throws -> T {
        try await sendMultipart(.post, path, fields: fields, files: files)
    }

    /// The raw body of a 2xx response, for PNG, SVG, VCF, ICS and other
    /// non-JSON payloads. Errors are still read from the JSON error envelope.
    func sendRaw(_ method: Method, _ path: String, query: [String: String] = [:], body: (any Encodable)? = nil,
                 accept: String = "*/*", authenticated: Bool = true) async throws -> Data {
        let encoded = try body.map { try encoder.encode($0) }
        let request = try makeRequest(method, path, query: query, body: encoded, accept: accept, authenticated: authenticated)
        return try await execute(request)
    }
}

/// One file in a `multipart/form-data` request.
public struct MultipartFile: Sendable, Hashable {
    /// The form field the server reads, e.g. `file`.
    public let fieldName: String
    public let filename: String
    /// e.g. `image/png`, `application/pdf`, `application/zip`.
    public let mimeType: String
    public let data: Data

    public init(fieldName: String = "file", filename: String, mimeType: String, data: Data) {
        self.fieldName = fieldName
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }

    /// The RFC 7578 body: one part per field (sorted by name), then one per
    /// file, each closed by CRLF, then the closing delimiter.
    static func formBody(boundary: String, fields: [String: String], files: [MultipartFile]) -> Data {
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(quoted(name))\"\r\n\r\n")
            append(value)
            append("\r\n")
        }
        for file in files {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(quoted(file.fieldName))\"; filename=\"\(quoted(file.filename))\"\r\n")
            append("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")
        return body
    }

    /// Makes a value safe inside a quoted header parameter: line breaks are
    /// dropped and `"` is percent-encoded, as browsers do.
    static func quoted(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\"", with: "%22")
    }
}
