import Foundation
import Observation
import ImageIO
import UniformTypeIdentifiers
import CardsiteKit

/// The workspace's stored images and files, with the storage it uses.
@MainActor
@Observable
final class UploadsModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all, images, files
        var id: String { rawValue }

        var kind: UploadKind? {
            switch self {
            case .all: return nil
            case .images: return .image
            case .files: return .document
            }
        }
    }

    /// Replaced when the filter changes: the server filters by `kind`.
    private(set) var list: PagedListModel<UploadItem>
    private(set) var filter: Filter = .all
    /// What the current workspace stores in all, from `GET /workspaces`.
    private(set) var storageBytes: Int64?
    private(set) var isUploading = false

    let client: APIClient
    @ObservationIgnored var onError: @MainActor (any Error) -> Void {
        didSet { list.onError = onError }
    }

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void = { _ in }) {
        self.client = client
        self.onError = onError
        self.list = UploadsModel.makeList(client: client, kind: nil)
        self.list.onError = onError
    }

    private static func makeList(client: APIClient, kind: UploadKind?) -> PagedListModel<UploadItem> {
        PagedListModel { page in try await client.uploads(page: page, kind: kind) }
    }

    var images: [UploadItem] { list.items.filter(\.isImage) }
    var files: [UploadItem] { list.items.filter { !$0.isImage } }

    func loadIfNeeded() async {
        guard case .idle = list.state else { return }
        await refresh()
    }

    func refresh() async {
        await list.refresh()
        await refreshStorage()
    }

    func setFilter(_ filter: Filter) async {
        guard filter != self.filter else { return }
        self.filter = filter
        let next = Self.makeList(client: client, kind: filter.kind)
        next.onError = onError
        list = next
        await next.refresh()
    }

    private func refreshStorage() async {
        do {
            let current = await client.workspaceID
            let workspaces = try await client.workspaces()
            let workspace = workspaces.first { $0.id == current } ?? workspaces.first(where: \.isPersonal)
            storageBytes = workspace?.storageBytes
        } catch is CancellationError {
        } catch {
            // The figure is secondary; the list shows its own errors.
            onError(error)
        }
    }

    // MARK: Writes

    /// Uploads one file after checking what the server would refuse.
    func upload(_ candidate: UploadCandidate) async throws {
        try candidate.validate()
        isUploading = true
        defer { isUploading = false }
        do {
            let file = MultipartFile(filename: candidate.filename, mimeType: candidate.mimeType, data: candidate.data)
            let item = try await client.upload(file, as: candidate.type)
            let kind: UploadKind = item.isImage ? .image : .document
            if filter.kind == nil || filter.kind == kind {
                list.insert(item)
            }
            storageBytes = (storageBytes ?? 0) + item.size
        } catch {
            onError(error)
            throw error
        }
    }

    func delete(_ item: UploadItem) async throws {
        do {
            try await client.deleteUpload(id: item.id)
            list.remove(id: item.id)
            if let bytes = storageBytes { storageBytes = max(0, bytes - item.size) }
        } catch {
            onError(error)
            throw error
        }
    }

    /// Sample data for previews; skips the first fetch.
    func seed(_ items: [UploadItem], storageBytes: Int64) {
        for item in items.reversed() { list.insert(item) }
        self.storageBytes = storageBytes
    }
}

/// A file picked for upload, before it is sent.
struct UploadCandidate: Sendable {
    let filename: String
    let mimeType: String
    let data: Data

    var type: UploadType { UploadRules.imageMIMETypes.contains(mimeType) ? .image : .file }

    enum Problem: LocalizedError {
        case tooLarge(Int64)
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .tooLarge(let bytes):
                let size = bytes.formatted(.byteCount(style: .file))
                let limit = UploadRules.maxBytes.formatted(.byteCount(style: .file))
                return String(localized: "This file is \(size). Uploads can be up to \(limit).")
            case .unsupported:
                return String(localized: "JPEG, PNG, GIF, WebP, PDF, TXT, CSV, JSON or ZIP.")
            }
        }
    }

    func validate() throws {
        let size = Int64(data.count)
        if size > UploadRules.maxBytes { throw Problem.tooLarge(size) }
        if !UploadRules.fileMIMETypes.contains(mimeType) { throw Problem.unsupported(mimeType) }
    }

    /// The content types `fileImporter` offers: what `/uploads` accepts.
    static let importableTypes: [UTType] = [.jpeg, .png, .gif, .webP, .pdf, .plainText, .commaSeparatedText, .json, .zip]

    /// A file from `fileImporter`. Reads it under security-scoped access.
    static func fromFile(at url: URL) throws -> UploadCandidate {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        if let size = values.fileSize, Int64(size) > UploadRules.maxBytes {
            throw Problem.tooLarge(Int64(size))
        }
        let type = values.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
        let data = try Data(contentsOf: url)
        return UploadCandidate(filename: url.lastPathComponent, mimeType: mimeType(for: type), data: data)
    }

    /// A photo from `PhotosPicker`. HEIC and other formats the server refuses
    /// are re-encoded as JPEG on the device.
    static func fromPhoto(data: Data, contentType: UTType?) throws -> UploadCandidate {
        let type = contentType ?? sniffedType(data) ?? .jpeg
        let mime = mimeType(for: type)
        if UploadRules.imageMIMETypes.contains(mime) {
            let ext = type.preferredFilenameExtension ?? "jpg"
            return UploadCandidate(filename: "photo.\(ext)", mimeType: mime, data: data)
        }
        guard let jpeg = jpegData(from: data) else { throw Problem.unsupported(mime) }
        return UploadCandidate(filename: "photo.jpg", mimeType: "image/jpeg", data: jpeg)
    }

    private static func mimeType(for type: UTType) -> String {
        // UTType reports text/comma-separated-values for CSV; the server
        // allows text/csv.
        if type.conforms(to: .commaSeparatedText) { return "text/csv" }
        if type.conforms(to: .json) { return "application/json" }
        return type.preferredMIMEType ?? "application/octet-stream"
    }

    private static func sniffedType(_ data: Data) -> UTType? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String? else { return nil }
        return UTType(identifier)
    }

    private static func jpegData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        var options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        if let orientation = properties[kCGImagePropertyOrientation] { options[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
