import Foundation

/// Uploads, data records and activity logs for the current workspace
/// (`/logs` is per user).
public extension APIClient {

    // MARK: Uploads

    /// `kind` filters by what the file is (`image` or `document`); nil lists all.
    func uploads(page: Int = 1, kind: UploadKind? = nil) async throws -> Page<UploadItem> {
        var query: [String: String] = [:]
        if let kind { query["kind"] = kind.rawValue }
        return try await sendPage("api/v1/uploads", page: page, query: query)
    }

    /// `POST /uploads` (multipart, fields `type` and `file`). The server
    /// sniffs the bytes, so `file.mimeType` must match the content, and it
    /// refuses anything over ``UploadRules/maxBytes``.
    func upload(_ file: MultipartFile, as type: UploadType) async throws -> UploadItem {
        try await sendMultipart("api/v1/uploads", fields: ["type": type.rawValue], files: [file])
    }

    func deleteUpload(id: Int) async throws {
        try await sendIgnoringBody(.delete, "api/v1/uploads/\(id)")
    }

    // MARK: Data records

    func dataRecords(page: Int = 1, kind: DataRecordKind? = nil) async throws -> Page<DataRecord> {
        var query: [String: String] = [:]
        if let kind { query["type"] = kind.rawValue }
        return try await sendPage("api/v1/data", page: page, query: query)
    }

    func dataRecord(id: Int) async throws -> DataRecord {
        try await send(.get, "api/v1/data/\(id)")
    }

    func deleteDataRecord(id: Int) async throws {
        try await sendIgnoringBody(.delete, "api/v1/data/\(id)")
    }

    // MARK: Activity logs

    /// `search` matches IP, city, browser and similar on the server.
    func activityLogs(page: Int = 1, search: String? = nil, device: LogDeviceType? = nil) async throws -> Page<ActivityLogEntry> {
        var query: [String: String] = [:]
        if let search, !search.isEmpty { query["search"] = search }
        if let device { query["device_type"] = device.rawValue }
        return try await sendPage("api/v1/logs", page: page, query: query)
    }
}
