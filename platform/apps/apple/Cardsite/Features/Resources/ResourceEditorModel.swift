import Foundation
import Observation
import UniformTypeIdentifiers
import CardsiteKit

/// Fields an inline error can belong to, across every resource editor.
enum ResourceField: Hashable {
    case slug, name, email, website, checkout, file, start, end
    case password, clicksLimit, expirationURL, unlock, secondaryURL, eventURL

    /// Where a server refusal belongs, from its classification and message.
    static func owning(_ error: APIError) -> ResourceField? {
        switch error {
        case .conflict:
            return .slug
        case .planCapability(let label):
            return (label ?? "").lowercased().contains("password") ? .password : nil
        case .invalid(let message):
            let text = message.lowercased()
            if text.contains("checkout") { return .checkout }
            if text.contains("file") || text.contains("archive") || text.contains("bundle") { return .file }
            if text.contains("name is required") { return .name }
            if text.contains("url is required") || text.contains("address") { return .slug }
            return nil
        default:
            return nil
        }
    }
}

/// The editor's state shared by every type, so one scaffold draws the
/// header, the save chrome, the form error and the danger zone for all.
@MainActor
protocol ResourceEditorState: AnyObject, Observable, Sendable {
    /// The saved resource; nil while creating.
    var item: ResourceItem? { get }
    var isDirty: Bool { get }
    var isSaving: Bool { get }
    var didJustSave: Bool { get }
    var formError: String? { get }
    var refreshError: APIError? { get }
    func save() async -> Bool
    func discard()
    func refresh() async
    func dismissRefreshError()
}

/// One resource's editor: the saved copy, the form being edited, save and
/// reload. Two copies of the form (saved and edited) make "unsaved
/// changes" a plain comparison, the way the link editor works.
///
/// `Form` is the type's own value (`VCardForm`, `EventForm`…). The closures
/// turn a resource into a form, check a form, and send it.
@MainActor
@Observable
final class ResourceEditorModel<Form: Equatable>: ResourceEditorState {
    var form: Form
    private(set) var savedForm: Form
    private(set) var item: ResourceItem?
    private(set) var errors: [ResourceField: String] = [:]
    private(set) var formError: String?
    private(set) var isSaving = false
    private(set) var didJustSave = false
    private(set) var refreshError: APIError?

    @ObservationIgnored private let makeForm: (ResourceItem) -> Form
    @ObservationIgnored private let validator: (Form) -> [ResourceField: String]
    @ObservationIgnored private let submit: @MainActor (Form, ResourceItem?) async throws -> ResourceItem
    @ObservationIgnored private let list: ResourceListModel

    /// - Parameters:
    ///   - item: the resource to edit, or nil to create one from `blank`.
    ///   - submit: creates (item nil) or saves, and returns the fresh resource.
    init(item: ResourceItem?, blank: @autoclosure () -> Form, list: ResourceListModel,
         makeForm: @escaping (ResourceItem) -> Form,
         validate: @escaping (Form) -> [ResourceField: String],
         submit: @escaping @MainActor (Form, ResourceItem?) async throws -> ResourceItem) {
        let initial = item.map(makeForm) ?? blank()
        self.form = initial
        self.savedForm = initial
        self.item = item
        self.list = list
        self.makeForm = makeForm
        self.validator = validate
        self.submit = submit
    }

    var isNew: Bool { item == nil }
    var isDirty: Bool { form != savedForm }

    /// Re-reads the resource. Edits in progress are kept; the saved copy
    /// moves underneath them.
    func refresh() async {
        guard let item else { return }
        do {
            let fresh = try await list.fetch(item)
            adopt(fresh, reseed: !isDirty)
            refreshError = nil
        } catch is CancellationError {
        } catch {
            refreshError = error.asAPIError
        }
    }

    func dismissRefreshError() { refreshError = nil }

    func discard() {
        form = savedForm
        errors = [:]
        formError = nil
    }

    /// Validates, sends and re-reads. Returns whether the server has it.
    @discardableResult
    func save() async -> Bool {
        guard !isSaving else { return false }
        formError = nil
        errors = validator(form)
        guard errors.isEmpty else { return false }

        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await submit(form, item)
            adopt(saved, reseed: true)
            list.didSave(saved)
            Haptics.success()
            didJustSave = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.didJustSave = false
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            list.onError(error)
            let apiError = (error as? APIError) ?? error.asAPIError
            if let local = error as? LocalizedError, !(error is APIError) {
                formError = local.errorDescription ?? apiError.localizedDescription
            } else if let field = ResourceField.owning(apiError) {
                errors[field] = apiError.localizedDescription
            } else {
                formError = apiError.localizedDescription
            }
            return false
        }
    }

    /// Clears the inline errors once the user edits again.
    func formChanged() {
        guard !errors.isEmpty || formError != nil else { return }
        errors = [:]
        formError = nil
    }

    private func adopt(_ fresh: ResourceItem, reseed: Bool) {
        item = fresh
        let next = makeForm(fresh)
        savedForm = next
        if reseed { form = next }
    }
}

// MARK: - Gate form

/// The gate as the form edits it: the click limit as typed, the password
/// as a change rather than a value (the digest is never shown).
struct GateForm: Equatable {
    var password: PasswordChange = .keep
    var clicksLimitText: String
    var expirationURL: String
    var sensitiveContent: Bool
    let hasPassword: Bool

    init(gate: ResourceGate = ResourceGate()) {
        clicksLimitText = gate.clicksLimit.map(String.init) ?? ""
        expirationURL = gate.expirationURL
        sensitiveContent = gate.sensitiveContent
        hasPassword = gate.hasPassword
    }

    /// - Parameter savedExpiration: for file links and static pages, which
    ///   can replace an expiration URL but not remove it; nil elsewhere.
    func validate(into errors: inout [ResourceField: String], savedExpiration: String? = nil) {
        let limit = clicksLimitText.trimmingCharacters(in: .whitespaces)
        if !limit.isEmpty, (Int(limit) ?? 0) <= 0 {
            errors[.clicksLimit] = String(localized: "Enter a whole number above 0, or leave it empty for no limit.")
        }
        let expiration = expirationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !expiration.isEmpty, Destination.normalized(expiration) == nil {
            errors[.expirationURL] = String(localized: "Enter a web address starting with https:// or a domain like example.com.")
        } else if expiration.isEmpty, let savedExpiration, !savedExpiration.isEmpty {
            errors[.expirationURL] = String(localized: "An expiration URL can be replaced here but not removed. Enter another address.")
        }
        if case .set(let value) = password, value.trimmingCharacters(in: .whitespaces).isEmpty {
            errors[.password] = String(localized: "A password can’t be only spaces.")
        }
    }

    /// The gate to send. Call after ``validate(into:savedExpiration:)``.
    var gate: ResourceGate {
        let limit = Int(clicksLimitText.trimmingCharacters(in: .whitespaces))
        let expiration = expirationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = expiration.isEmpty ? "" : (Destination.normalized(expiration)?.absoluteString ?? expiration)
        return ResourceGate(clicksLimit: (limit ?? 0) > 0 ? limit : nil, expirationURL: normalized,
                            sensitiveContent: sensitiveContent, hasPassword: hasPassword)
    }
}

// MARK: - Address form

/// Slug and domain, checked the same way for every type.
struct AddressForm: Equatable {
    var slug: String
    var domainID: Int?

    init(slug: String = Slug.random(), domainID: Int? = nil) {
        self.slug = slug
        self.domainID = domainID
    }

    func validate(into errors: inout [ResourceField: String]) {
        let trimmed = slug.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            errors[.slug] = String(localized: "An address is required")
        } else if let problem = Slug.problem(with: trimmed) {
            errors[.slug] = Slug.message(for: problem)
        }
    }

    var trimmedSlug: String { slug.trimmingCharacters(in: .whitespaces) }
}

// MARK: - Picked file

/// A file chosen for a file link or static page, checked on the device
/// against what the server accepts before it is sent.
struct PickedFile: Equatable, Sendable {
    let filename: String
    let mimeType: String
    let data: Data

    var size: Int64 { Int64(data.count) }
    var multipart: MultipartFile { MultipartFile(filename: filename, mimeType: mimeType, data: data) }

    enum Problem: LocalizedError {
        case tooLarge(Int64)
        case unsupported(allowed: String)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .tooLarge(let bytes):
                let size = bytes.formatted(.byteCount(style: .file))
                let limit = ResourceUploadRules.maxBytes.formatted(.byteCount(style: .file))
                return String(localized: "This file is \(size). Files can be up to \(limit).")
            case .unsupported(let allowed):
                return allowed
            case .unreadable:
                return String(localized: "That file couldn’t be read.")
            }
        }
    }

    /// What a file link accepts, as the web words it.
    static let fileLinkAccepts = String(localized: "Images (JPEG, PNG, GIF, WebP), PDF, TXT, CSV, JSON, or ZIP — up to 10 MB.")
    static let staticPageAccepts = String(localized: "An HTML file, or a ZIP of a site with index.html at its root — up to 10 MB.")

    static let fileLinkTypes: [UTType] = [.jpeg, .png, .gif, .webP, .pdf, .plainText, .commaSeparatedText, .json, .zip]
    static let staticPageTypes: [UTType] = [.html, .zip]

    /// Reads a file from `fileImporter` under security-scoped access, and
    /// checks it against `allowed` MIME types and the size cap.
    static func fromFile(at url: URL, allowed: Set<String>, allowedDescription: String) throws -> PickedFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        if let size = values?.fileSize, Int64(size) > ResourceUploadRules.maxBytes {
            throw Problem.tooLarge(Int64(size))
        }
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
        let mime = mimeType(for: type)
        guard allowed.contains(mime) else { throw Problem.unsupported(allowed: allowedDescription) }
        guard let data = try? Data(contentsOf: url) else { throw Problem.unreadable }
        let file = PickedFile(filename: url.lastPathComponent, mimeType: mime, data: data)
        try file.checkSize()
        return file
    }

    /// A photo from `PhotosPicker`, sent as it is when the server takes its
    /// format. HEIC and the like are refused here rather than converted, so
    /// the file people download is the one that was picked.
    static func fromPhoto(data: Data, contentType: UTType?, allowedDescription: String) throws -> PickedFile {
        guard let type = contentType else { throw Problem.unsupported(allowed: allowedDescription) }
        let mime = mimeType(for: type)
        guard UploadRules.imageMIMETypes.contains(mime) else { throw Problem.unsupported(allowed: allowedDescription) }
        let ext = type.preferredFilenameExtension ?? "jpg"
        let file = PickedFile(filename: "photo.\(ext)", mimeType: mime, data: data)
        try file.checkSize()
        return file
    }

    func checkSize() throws {
        if size > ResourceUploadRules.maxBytes { throw Problem.tooLarge(size) }
    }

    /// The MIME type the server's allow-lists use for a content type.
    static func mimeType(for type: UTType) -> String {
        if type.conforms(to: .commaSeparatedText) { return "text/csv" }
        if type.conforms(to: .json) { return "application/json" }
        if type.conforms(to: .html) { return "text/html" }
        if type.conforms(to: .zip) { return "application/zip" }
        if type.conforms(to: .plainText) { return "text/plain" }
        return type.preferredMIMEType ?? "application/octet-stream"
    }
}
