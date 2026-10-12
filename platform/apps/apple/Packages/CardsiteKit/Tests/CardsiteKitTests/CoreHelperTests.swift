import XCTest
@testable import CardsiteKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Tests for the transport helpers the domain files build on (`sendPage`,
// `sendMultipart`, `sendRaw`, the workspace header) and for `JSONValue`.

private func queryItems(_ request: URLRequest?) -> [String: String] {
    guard let url = request?.url,
          let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
}

// MARK: - Paging

final class PagingTests: XCTestCase {
    func testDefaultPageSendsBothPageSizeNames() async throws {
        let stub = try StubTransport(fixtures: "06b-links-list-200")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        let page: Page<Resource> = try await client.sendPage("api/v1/links", page: 2)
        XCTAssertEqual(page.items.count, 1)
        let query = queryItems(stub.lastRequest)
        XCTAssertEqual(query["page"], "2")
        XCTAssertEqual(query["results_per_page"], String(APIClient.pageSize))
        XCTAssertEqual(query["per_page"], String(APIClient.pageSize), "/logs and /internal-notifications read per_page")
    }

    func testExtraQueryItemsPassThroughAndSizeOverrides() async throws {
        let stub = try StubTransport(fixtures: "22e-links-list-paged-200")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        let page: Page<Resource> = try await client.sendPage("api/v1/links", page: 1, query: [
            "results_per_page": "2",
            "search": "spring menu",
            "type": "link",
        ])
        let query = queryItems(stub.lastRequest)
        XCTAssertEqual(query["page"], "1")
        XCTAssertEqual(query["results_per_page"], "2")
        XCTAssertEqual(query["per_page"], "2", "one size, sent under both names")
        XCTAssertEqual(query["search"], "spring menu")
        XCTAssertEqual(query["type"], "link")
        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.meta.perPage, 2)
        XCTAssertTrue(page.hasMore)
        XCTAssertNil(stub.lastRequest?.value(forHTTPHeaderField: "X-Requested-With"), "reads carry no CSRF header")
    }

    func testPerPageNameAlsoSetsTheSize() async throws {
        let stub = try StubTransport(fixtures: "26t-internal-notifications-list-200")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        let page: Page<JSONValue> = try await client.sendPage("api/v1/internal-notifications", page: 1, query: ["per_page": "10"])
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?["title"]?.stringValue, "Welcome to Cardsite")
        let query = queryItems(stub.lastRequest)
        XCTAssertEqual(query["per_page"], "10")
        XCTAssertEqual(query["results_per_page"], "10")
    }

    func testNullPageIsEmpty() async throws {
        let stub = try StubTransport(fixtures: "26s-internal-notifications-empty-200")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        let page: Page<JSONValue> = try await client.sendPage("api/v1/internal-notifications", page: 1)
        XCTAssertTrue(page.items.isEmpty)
        XCTAssertEqual(page.meta.total, 0)
        XCTAssertFalse(page.hasMore)
    }
}

// MARK: - Headers

final class HeaderTests: XCTestCase {
    func testWorkspaceHeaderFollowsSetWorkspace() async throws {
        let stub = try StubTransport(fixtures: "05-workspaces-200", "05-workspaces-200", "05-workspaces-200")
        let client = APIClient(baseURL: base, token: "t", transport: stub)

        await client.setWorkspace(1)
        _ = try await client.workspaces()
        XCTAssertEqual(stub.lastRequest?.value(forHTTPHeaderField: "X-Workspace-ID"), "1")

        await client.setWorkspace(2)
        _ = try await client.workspaces()
        XCTAssertEqual(stub.lastRequest?.value(forHTTPHeaderField: "X-Workspace-ID"), "2")

        await client.setWorkspace(nil)
        _ = try await client.workspaces()
        XCTAssertNil(stub.lastRequest?.value(forHTTPHeaderField: "X-Workspace-ID"), "nil selects the personal workspace")
    }

    func testForeignWorkspaceIsInvalidNotSessionExpired() async throws {
        let stub = try StubTransport(fixtures: "26z11-links-list-foreign-workspace")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        await client.setWorkspace(999_999_999)
        do {
            _ = try await client.links()
            XCTFail("expected throw")
        } catch let error as APIError {
            XCTAssertEqual(error, .invalid("You are not a member of this workspace"))
        }
    }

    func testPatchIsAWrite() async throws {
        let stub = try StubTransport(fixtures: "21b-projects-update-200")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        try await client.sendIgnoringBody(.patch, "api/v1/projects/1", body: ["name": "x"])
        XCTAssertEqual(stub.lastRequest?.httpMethod, "PATCH")
        XCTAssertEqual(stub.lastRequest?.value(forHTTPHeaderField: "X-Requested-With"), "XMLHttpRequest")
    }

    func testCredentialCheckedWritesKeepTheSession() async throws {
        let stub = try StubTransport(fixtures: "26g-account-password-401", "26g-account-password-401")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        let body = ["current_password": "wrong", "new_password": "another-pass-123"]
        do {
            try await client.sendIgnoringBody(.put, "api/v1/account/password", body: body, credentialCheck: true)
            XCTFail("expected throw")
        } catch let error as APIError {
            XCTAssertEqual(error, .rejected("Current password is incorrect"))
        }
        do {
            try await client.sendIgnoringBody(.put, "api/v1/account/password", body: body)
            XCTFail("expected throw")
        } catch let error as APIError {
            XCTAssertEqual(error, .sessionExpired, "without credentialCheck a 401 ends the session, so password and 2FA calls must pass it")
        }
    }
}

// MARK: - Multipart

final class MultipartTests: XCTestCase {
    func testFormBodyShape() {
        let file = MultipartFile(fieldName: "file", filename: "he\"llo\r\n.txt", mimeType: "text/plain", data: Data("hi".utf8))
        let body = MultipartFile.formBody(boundary: "B", fields: ["url": "launch", "a": "1"], files: [file])
        let expected = "--B\r\n"
            + "Content-Disposition: form-data; name=\"a\"\r\n\r\n"
            + "1\r\n"
            + "--B\r\n"
            + "Content-Disposition: form-data; name=\"url\"\r\n\r\n"
            + "launch\r\n"
            + "--B\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"he%22llo.txt\"\r\n"
            + "Content-Type: text/plain\r\n\r\n"
            + "hi\r\n"
            + "--B--\r\n"
        XCTAssertEqual(String(decoding: body, as: UTF8.self), expected)
    }

    func testBinaryFileBytesAreUntouched() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x0D, 0x0A, 0xFF])
        let body = MultipartFile.formBody(boundary: "B", fields: [:], files: [
            MultipartFile(filename: "a.png", mimeType: "image/png", data: bytes),
        ])
        XCTAssertNotNil(body.range(of: bytes), "file data is copied verbatim")
        XCTAssertTrue(String(decoding: body, as: UTF8.self).hasSuffix("\r\n--B--\r\n"))
    }

    func testSendMultipartHeadersAndDecode() async throws {
        let stub = try StubTransport(fixtures: "25m-files-create-201")
        let client = APIClient(baseURL: base, token: "abc", transport: stub)
        await client.setWorkspace(7)
        let file = MultipartFile(filename: "hello.txt", mimeType: "text/plain", data: Data("hello".utf8))
        let created: Resource = try await client.sendMultipart(.post, "api/v1/files", fields: ["url": "hello"], files: [file])
        XCTAssertEqual(created.type, "file")

        let request = try XCTUnwrap(stub.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.test/api/v1/files")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Requested-With"), "XMLHttpRequest")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Workspace-ID"), "7")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.hasPrefix("--\(boundary)\r\n"))
        XCTAssertTrue(body.contains("name=\"url\"\r\n\r\nhello\r\n"))
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"hello.txt\"\r\nContent-Type: text/plain\r\n\r\nhello\r\n"))
        XCTAssertTrue(body.hasSuffix("--\(boundary)--\r\n"))
    }

    func testSendMultipartPutAndPathOnlyOverload() async throws {
        let stub = try StubTransport(fixtures: "25n-files-update-200", "25p-static-create-201")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        let updated: Resource = try await client.sendMultipart(.put, "api/v1/files/10", fields: ["force_download_is_enabled": "true"], files: [])
        XCTAssertEqual(stub.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(updated.type, "file")
        let page = MultipartFile(filename: "index.html", mimeType: "text/html", data: Data("<h1>Hi</h1>".utf8))
        let site: Resource = try await client.sendMultipart("api/v1/static", fields: ["url": "site"], files: [page])
        XCTAssertEqual(stub.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(site.type, "static")
    }

    func testSendMultipartWithoutTokenFailsLocally() async throws {
        let stub = StubTransport([])
        let client = APIClient(baseURL: base, transport: stub)
        do {
            let _: Resource = try await client.sendMultipart("api/v1/files", fields: [:], files: [])
            XCTFail("expected throw")
        } catch let error as APIError {
            XCTAssertEqual(error, .sessionExpired)
            XCTAssertTrue(stub.requests.isEmpty)
        }
    }
}

// MARK: - Raw bodies

final class RawTests: XCTestCase {
    func testSendRawReturnsBytes() async throws {
        let vcard = Data("BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Ada\r\nEND:VCARD\r\n".utf8)
        let stub = StubTransport([(200, vcard, ["Content-Type": "text/vcard"])])
        let client = APIClient(baseURL: base, token: "abc", transport: stub)
        await client.setWorkspace(3)
        let data = try await client.sendRaw(.get, "api/v1/vcards/7/download", query: ["size": "512"])
        XCTAssertEqual(data, vcard)
        let request = try XCTUnwrap(stub.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "*/*")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Workspace-ID"), "3")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Requested-With"))
        XCTAssertEqual(queryItems(request)["size"], "512")
    }

    func testSendRawWriteEncodesJSONAndSendsCSRF() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let stub = StubTransport([(200, png, ["Content-Type": "image/png"])])
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        let data = try await client.sendRaw(.post, "api/v1/qr-codes/render", body: ["type": "url"])
        XCTAssertEqual(data, png)
        let request = try XCTUnwrap(stub.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Requested-With"), "XMLHttpRequest")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self), #"{"type":"url"}"#)
    }

    func testSendRawErrorsUseTheEnvelope() async throws {
        let stub = try StubTransport(fixtures: "22g-links-get-404")
        let client = APIClient(baseURL: base, token: "t", transport: stub)
        do {
            _ = try await client.sendRaw(.get, "api/v1/vcards/1/download")
            XCTFail("expected throw")
        } catch let error as APIError {
            XCTAssertEqual(error, .invalid("Link not found"))
        }
    }
}

// MARK: - JSONValue

final class JSONValueTests: XCTestCase {
    private func decode(_ json: String) throws -> JSONValue {
        try CardsiteJSON.decoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    func testDecodesEveryCase() throws {
        let value = try decode(#"{"s":"x","b":true,"i":7,"d":1.5,"a":[1,"y",false,null],"o":{"k":"v"},"n":null}"#)
        XCTAssertEqual(value, .object([
            "s": .string("x"),
            "b": .bool(true),
            "i": .int(7),
            "d": .double(1.5),
            "a": .array([.int(1), .string("y"), .bool(false), .null]),
            "o": .object(["k": .string("v")]),
            "n": .null,
        ]))
    }

    func testNumbersAreNotBooleans() throws {
        XCTAssertEqual(try decode("[true,1,0,false]"), .array([.bool(true), .int(1), .int(0), .bool(false)]))
    }

    func testRoundTripThroughTheEncoder() throws {
        let value: JSONValue = ["name": "Shop", "order": 2, "ratio": 0.5, "on": true, "tags": ["a", "b"], "gone": .null]
        let data = try CardsiteJSON.encoder().encode(value)
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       #"{"gone":null,"name":"Shop","on":true,"order":2,"ratio":0.5,"tags":["a","b"]}"#)
        XCTAssertEqual(try CardsiteJSON.decoder().decode(JSONValue.self, from: data), value)
    }

    func testRoundTripOfALiveLink() throws {
        let original = try fixture("22a-links-create-full-201").body
        let value = try CardsiteJSON.decoder().decode(JSONValue.self, from: original)
        let reencoded = try CardsiteJSON.encoder().encode(value)
        XCTAssertEqual(try CardsiteJSON.decoder().decode(JSONValue.self, from: reencoded), value)
        let expected = try JSONSerialization.jsonObject(with: original) as? NSDictionary
        let actual = try JSONSerialization.jsonObject(with: reencoded) as? NSDictionary
        XCTAssertEqual(actual, expected, "nothing is lost or retyped")
    }

    func testAccessorsOnLiveSettings() throws {
        let link = try CardsiteJSON.decoder().decode(JSONValue.self, from: fixture("22a-links-create-full-201").body)
        let data = try XCTUnwrap(link["data"])
        XCTAssertEqual(data["settings"]?["clicks_limit"]?.intValue, 100)
        XCTAssertEqual(data["settings"]?["http_status_code"]?.intValue, 301)
        XCTAssertEqual(data["settings"]?["utm_source"]?.stringValue, "newsletter")
        XCTAssertEqual(data["settings"]?["sensitive_content"]?.boolValue, true)
        XCTAssertEqual(data["display_rules"]?["countries"]?.arrayValue?.count, 2)
        XCTAssertEqual(data["display_rules"]?["countries"]?[0]?.stringValue, "GB")
        XCTAssertNil(data["display_rules"]?["countries"]?[9])
        XCTAssertNil(data["settings"]?["missing"])
        XCTAssertNil(data["id"]?["nested"], "subscripting a non-object is nil")
        XCTAssertEqual(data["settings"]?.objectValue?.isEmpty, false)
    }

    func testNumericAccessors() {
        XCTAssertEqual(JSONValue.double(2.0).intValue, 2)
        XCTAssertNil(JSONValue.double(2.5).intValue)
        XCTAssertEqual(JSONValue.int(3).doubleValue, 3.0)
        XCTAssertNil(JSONValue.string("3").intValue)
        XCTAssertNil(JSONValue.bool(true).intValue)
        XCTAssertTrue(JSONValue.null.isNull)
    }

    func testHashable() {
        let set: Set<JSONValue> = [.int(1), .int(1), .string("1"), ["a": 1], ["a": 1]]
        XCTAssertEqual(set.count, 3)
    }
}
