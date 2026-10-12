import Foundation

/// vCards, events, payment links, file links, static pages and splash pages.
/// The rules each call follows are in Models+Resources.swift.
///
/// Every save re-reads the resource afterwards, as the link editor does: the
/// re-read is what the list and the editor show, so neither depends on the
/// shape of a PUT response.
public extension APIClient {

    // MARK: Link-backed resources

    /// One page of a type's resources. A non-empty `search` is sent as
    /// `search=`; as of 2026-10-12 these list handlers read only `page` and
    /// `results_per_page`, so callers also filter what they have loaded.
    func managedResources(_ type: ManagedResourceType, page: Int, search: String? = nil) async throws -> Page<ManagedResource> {
        var query: [String: String] = [:]
        if let search = search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
            query["search"] = search
        }
        return try await sendPage(type.path, page: page, query: query)
    }

    func managedResource(_ type: ManagedResourceType, id: Int) async throws -> ManagedResource {
        try await send(.get, "\(type.path)/\(id)")
    }

    func deleteManagedResource(_ type: ManagedResourceType, id: Int) async throws {
        try await sendIgnoringBody(.delete, "\(type.path)/\(id)")
    }

    /// Turns the address on or off and returns the fresh resource. File links
    /// and static pages take the switch as a multipart field.
    func setManagedResourceEnabled(_ type: ManagedResourceType, id: Int, isEnabled: Bool) async throws -> ManagedResource {
        if type.usesMultipart {
            let _: JSONValue = try await sendMultipart(.put, "\(type.path)/\(id)",
                                                       fields: ["is_enabled": isEnabled ? "true" : "false"], files: [])
        } else {
            try await sendIgnoringBody(.put, "\(type.path)/\(id)", body: ["is_enabled": JSONValue.bool(isEnabled)])
        }
        return try await managedResource(type, id: id)
    }

    /// Copies a vCard, event or payment link to `<slug>-copy` (then
    /// `-copy-2`, …). The copy starts disabled with no clicks. File links and
    /// static pages can't be copied (422): check
    /// ``ManagedResourceType/supportsDuplicate`` first.
    func duplicateManagedResource(id: Int) async throws -> ManagedResource {
        try await send(.post, "api/v1/links/\(id)/duplicate")
    }

    // MARK: vCards

    func createVCard(_ draft: VCardDraft) async throws -> ManagedResource {
        let created: ManagedResource = try await send(.post, ManagedResourceType.vcard.path, body: draft.createBody)
        return try await managedResource(.vcard, id: created.id)
    }

    /// Sends the whole settings object (PUT replaces it).
    func updateVCard(id: Int, _ draft: VCardDraft) async throws -> ManagedResource {
        try await sendIgnoringBody(.put, "\(ManagedResourceType.vcard.path)/\(id)", body: draft.updateBody)
        return try await managedResource(.vcard, id: id)
    }

    /// The card as a vCard 3.0 file (`text/vcard`), as the server builds it.
    func vcardFile(id: Int) async throws -> Data {
        try await sendRaw(.get, "\(ManagedResourceType.vcard.path)/\(id)/download", accept: "text/vcard, */*")
    }

    // MARK: Events

    func createEvent(_ draft: EventDraft) async throws -> ManagedResource {
        let created: ManagedResource = try await send(.post, ManagedResourceType.event.path, body: draft.createBody)
        return try await managedResource(.event, id: created.id)
    }

    func updateEvent(id: Int, _ draft: EventDraft) async throws -> ManagedResource {
        try await sendIgnoringBody(.put, "\(ManagedResourceType.event.path)/\(id)", body: draft.updateBody)
        return try await managedResource(.event, id: id)
    }

    /// The public `.ics` (`GET /api/public/events/{slug}/ics`). No token is
    /// sent. The server answers 404 for a disabled or lapsed event, 403 for
    /// a password-gated or sensitive one, and resolves the slug on the
    /// default domain.
    func eventCalendarFile(slug: String) async throws -> Data {
        let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        return try await sendRaw(.get, "api/public/events/\(encoded)/ics", accept: "text/calendar, */*", authenticated: false)
    }

    // MARK: Payment links

    func createPaymentLink(_ draft: PaymentLinkDraft) async throws -> ManagedResource {
        let created: ManagedResource = try await send(.post, ManagedResourceType.paymentLink.path, body: draft.createBody)
        return try await managedResource(.paymentLink, id: created.id)
    }

    func updatePaymentLink(id: Int, _ draft: PaymentLinkDraft) async throws -> ManagedResource {
        try await sendIgnoringBody(.put, "\(ManagedResourceType.paymentLink.path)/\(id)", body: draft.updateBody)
        return try await managedResource(.paymentLink, id: id)
    }

    // MARK: File links

    /// `file.fieldName` must be `file`. The server sniffs the bytes against
    /// `file.mimeType` and refuses anything over 10 MB.
    func createFileLink(_ draft: FileLinkDraft, file: MultipartFile) async throws -> ManagedResource {
        let created: ManagedResource = try await sendMultipart(ManagedResourceType.file.path,
                                                               fields: draft.fields(saved: nil), files: [file])
        return try await managedResource(.file, id: created.id)
    }

    /// `file` nil keeps the stored file and changes only the settings.
    func updateFileLink(id: Int, _ draft: FileLinkDraft, savedGate: ResourceGate, file: MultipartFile? = nil) async throws -> ManagedResource {
        let _: JSONValue = try await sendMultipart(.put, "\(ManagedResourceType.file.path)/\(id)",
                                                   fields: draft.fields(saved: savedGate), files: file.map { [$0] } ?? [])
        return try await managedResource(.file, id: id)
    }

    // MARK: Static pages

    /// An HTML page, or a ZIP of a site (index.html at its root).
    func createStaticPage(_ draft: StaticPageDraft, file: MultipartFile) async throws -> ManagedResource {
        let created: ManagedResource = try await sendMultipart(ManagedResourceType.staticPage.path,
                                                               fields: draft.fields(saved: nil), files: [file])
        return try await managedResource(.staticPage, id: created.id)
    }

    func updateStaticPage(id: Int, _ draft: StaticPageDraft, savedGate: ResourceGate, file: MultipartFile? = nil) async throws -> ManagedResource {
        let _: JSONValue = try await sendMultipart(.put, "\(ManagedResourceType.staticPage.path)/\(id)",
                                                   fields: draft.fields(saved: savedGate), files: file.map { [$0] } ?? [])
        return try await managedResource(.staticPage, id: id)
    }

    // MARK: Splash pages

    func splashPages(page: Int) async throws -> Page<SplashPage> {
        try await sendPage("api/v1/splash-pages", page: page)
    }

    func splashPage(id: Int) async throws -> SplashPage {
        try await send(.get, "api/v1/splash-pages/\(id)")
    }

    /// A blank name is refused (400 "Name is required").
    func createSplashPage(_ draft: SplashPageDraft) async throws -> SplashPage {
        try await send(.post, "api/v1/splash-pages", body: draft.body)
    }

    func updateSplashPage(id: Int, _ draft: SplashPageDraft) async throws -> SplashPage {
        try await sendIgnoringBody(.put, "api/v1/splash-pages/\(id)", body: draft.body)
        return try await splashPage(id: id)
    }

    func deleteSplashPage(id: Int) async throws {
        try await sendIgnoringBody(.delete, "api/v1/splash-pages/\(id)")
    }
}
