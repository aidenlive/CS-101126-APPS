#if DEBUG
import Foundation
import CardsiteKit

/// An ``HTTPTransport`` that answers every API call from an in-memory
/// ``FixtureStore`` seeded from the live-captured contract fixtures
/// (`ContractTests/fixtures`, copied to `Debug/Fixtures`). Creates, edits and
/// deletes change the store, so lists reflect them for the rest of the launch.
///
/// Routes are matched by method and path pattern. An unknown route gets the
/// server's 404 envelope, `{"error":{"title":"Not found","code":404}}`.
/// Debug builds only; enable with `-CardsiteFixtures` (see ``FixtureMode``).
struct FixtureTransport: HTTPTransport {
    let store: FixtureStore

    init(store: FixtureStore = FixtureStore(empty: FixtureMode.isEmpty)) {
        self.store = store
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let latency = FixtureMode.latency
        if latency > .zero {
            try await Task.sleep(for: latency)
        }
        let reply = await store.respond(to: FixtureRequest(request))
        let data = try JSONEncoder().encode(reply.body)
        let url = request.url ?? URL(fileURLWithPath: "/")
        let headers = [
            "Content-Type": "application/json; charset=utf-8",
            "X-Request-Id": "fixture-\(UUID().uuidString.prefix(8))",
        ]
        guard let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }
}

/// The parts of a `URLRequest` the fixture routes read.
struct FixtureRequest: Sendable {
    let method: String
    /// Path segments after `api/v1`, e.g. `["links", "12", "duplicate"]`.
    let path: [String]
    let query: [String: String]
    /// The JSON body's top-level members, or the text fields of a
    /// multipart body. A file part `file` appears as `file.filename`.
    let body: [String: JSONValue]
    let hasBearer: Bool
    let workspaceID: Int?

    init(method: String, path: [String], query: [String: String] = [:], body: [String: JSONValue] = [:],
         hasBearer: Bool = true, workspaceID: Int? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.hasBearer = hasBearer
        self.workspaceID = workspaceID
    }

    init(_ request: URLRequest) {
        method = request.httpMethod ?? "GET"

        var segments = (request.url?.path ?? "").split(separator: "/").map(String.init)
        if let v1 = segments.firstIndex(of: "v1"), v1 > 0, segments[v1 - 1] == "api" {
            segments = Array(segments[(v1 + 1)...])
        }
        path = segments

        var query: [String: String] = [:]
        if let url = request.url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items { query[item.name] = item.value ?? "" }
        }
        self.query = query

        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        if let data = request.httpBody, !data.isEmpty {
            if contentType.hasPrefix("multipart/form-data") {
                body = Self.multipartFields(data, contentType: contentType)
            } else {
                body = (try? JSONDecoder().decode(JSONValue.self, from: data))?.objectValue ?? [:]
            }
        } else {
            body = [:]
        }

        hasBearer = request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true
        workspaceID = request.value(forHTTPHeaderField: "X-Workspace-ID").flatMap(Int.init)
    }

    /// Text fields of a `multipart/form-data` body. File contents are not
    /// kept; a file part contributes `<field>.filename`.
    static func multipartFields(_ data: Data, contentType: String) -> [String: JSONValue] {
        guard let range = contentType.range(of: "boundary=") else { return [:] }
        let boundary = contentType[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        let text = String(decoding: data, as: UTF8.self)
        var fields: [String: JSONValue] = [:]
        for part in text.components(separatedBy: "--" + boundary) {
            guard let split = part.range(of: "\r\n\r\n") else { continue }
            let headers = part[..<split.lowerBound]
            guard let name = Self.parameter("name", in: headers) else { continue }
            var value = String(part[split.upperBound...])
            if value.hasSuffix("\r\n") { value.removeLast(2) }
            if let filename = Self.parameter("filename", in: headers) {
                fields[name + ".filename"] = .string(filename)
            } else {
                fields[name] = .string(value)
            }
        }
        return fields
    }

    private static func parameter(_ key: String, in headers: Substring) -> String? {
        guard let start = headers.range(of: " \(key)=\"") ?? headers.range(of: ";\(key)=\"") else { return nil }
        let rest = headers[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }
}

/// A status and a JSON body, as the server would send them.
struct FixtureReply: Sendable {
    let status: Int
    let body: JSONValue

    static func ok(_ data: JSONValue, status: Int = 200) -> FixtureReply {
        FixtureReply(status: status, body: ["data": data])
    }

    static func page(_ rows: [JSONValue], page: Int, perPage: Int, total: Int) -> FixtureReply {
        FixtureReply(status: 200, body: [
            "data": rows.isEmpty ? .null : .array(rows),
            "meta": ["page": .int(page), "per_page": .int(perPage), "total": .int(total)],
        ])
    }

    static func message(_ text: String) -> FixtureReply {
        ok(["message": .string(text)])
    }

    /// The server's error envelope, `{"error":{"title","code",…}}`.
    static func error(_ status: Int, _ title: String, extras: [String: JSONValue] = [:]) -> FixtureReply {
        var error = extras
        error["title"] = .string(title)
        error["code"] = .int(status)
        return FixtureReply(status: status, body: ["error": .object(error)])
    }

    static let notFound = error(404, "Not found")
}
#endif
