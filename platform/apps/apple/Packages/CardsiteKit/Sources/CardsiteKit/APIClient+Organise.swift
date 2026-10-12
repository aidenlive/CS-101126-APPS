import Foundation

/// Projects, custom domains and pixels in the current workspace: full CRUD
/// for the Organise screens. Pickers keep using ``projectOptions()`` and
/// ``domainOptions()`` (APIClient+Reference.swift).
///
/// Server: handlers/projects.go, domains.go, pixels.go. Fixtures 21a–21h.
/// Each create counts against the owner's plan (projects, domains and
/// pixels limits), so a full plan is ``APIError/planLimit(limit:current:max:)``.
extension APIClient {

    // MARK: Projects

    public func projects(page: Int = 1) async throws -> Page<Project> {
        try await sendPage("api/v1/projects", page: page)
    }

    /// `POST /projects`. A blank name is a 400.
    public func createProject(_ input: ProjectInput) async throws -> Project {
        try await send(.post, "api/v1/projects", body: input.body)
    }

    /// `PUT /projects/{id}`: renames and recolours.
    public func updateProject(id: Int, _ input: ProjectInput) async throws -> Project {
        try await send(.put, "api/v1/projects/\(id)", body: input.body)
    }

    public func deleteProject(id: Int) async throws {
        try await sendIgnoringBody(.delete, "api/v1/projects/\(id)")
    }

    // MARK: Custom domains

    public func customDomains(page: Int = 1) async throws -> Page<CustomDomain> {
        try await sendPage("api/v1/domains", page: page)
    }

    public func customDomain(id: Int) async throws -> CustomDomain {
        try await send(.get, "api/v1/domains/\(id)")
    }

    /// `POST /domains`. The new domain starts enabled and unverified.
    public func createCustomDomain(_ input: CustomDomainInput) async throws -> CustomDomain {
        try await send(.post, "api/v1/domains", body: input.createBody)
    }

    /// `PUT /domains/{id}` with only the fields that differ from `original`.
    /// Returns `original` without a request when nothing changed.
    public func updateCustomDomain(_ original: CustomDomain, to input: CustomDomainInput) async throws -> CustomDomain {
        let body = input.updateBody(from: original)
        guard !body.isEmpty else { return original }
        return try await send(.put, "api/v1/domains/\(original.id)", body: body)
    }

    public func deleteCustomDomain(id: Int) async throws {
        try await sendIgnoringBody(.delete, "api/v1/domains/\(id)")
    }

    /// `POST /domains/{id}/verify`: a live DNS check that the host points at
    /// this deployment. Both outcomes are recorded on the domain.
    ///
    /// - 200: ``DomainVerification/verified(_:)``.
    /// - 422: ``DomainVerification/notVerified(_:title:message:)``, with the
    ///   server's advice ("Point … at …, then verify again.").
    /// - 503: ``DomainVerification/unavailable(_:)``, not a maintenance
    ///   window: the deployment can't run the check.
    /// - Anything else throws, as every call does (404 is ``APIError/invalid(_:)``).
    public func verifyCustomDomain(id: Int) async throws -> DomainVerification {
        let request = try makeRequest(.post, "api/v1/domains/\(id)/verify", body: nil, authenticated: true)
        let (status, data) = try await exchange(request, accepting: [422, 503])
        let envelope: VerificationEnvelope
        do {
            envelope = try CardsiteJSON.decoder().decode(VerificationEnvelope.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
        switch status {
        case 422:
            let title = envelope.error?.title ?? String(localized: "This domain doesn't point here yet.")
            return .notVerified(envelope.data, title: title, message: envelope.error?.message)
        case 503:
            return .unavailable(envelope.error?.message ?? envelope.error?.title
                ?? String(localized: "Domain verification is not available right now."))
        default:
            guard let domain = envelope.data else { throw APIError.decoding("Empty data for domain verification") }
            return .verified(domain)
        }
    }

    // MARK: Pixels

    public func pixels(page: Int = 1) async throws -> Page<TrackingPixel> {
        try await sendPage("api/v1/pixels", page: page)
    }

    /// `GET /pixels/types`: every provider, in the server's order.
    public func pixelTypes() async throws -> [PixelType] {
        let list: [PixelType]? = try await sendOptional(.get, "api/v1/pixels/types")
        return list ?? []
    }

    /// `POST /pixels`. A blank name or type is a 400.
    public func createPixel(_ input: PixelInput) async throws -> TrackingPixel {
        try await send(.post, "api/v1/pixels", body: input.body)
    }

    /// `PUT /pixels/{id}`: fixes a name, provider or id without detaching
    /// the pixel from the links that carry it.
    public func updatePixel(id: Int, _ input: PixelInput) async throws -> TrackingPixel {
        try await send(.put, "api/v1/pixels/\(id)", body: input.body)
    }

    public func deletePixel(id: Int) async throws {
        try await sendIgnoringBody(.delete, "api/v1/pixels/\(id)")
    }
}

/// `{data, error}`: the verify endpoint's 422 carries both.
private struct VerificationEnvelope: Decodable {
    let data: CustomDomain?
    let error: ErrorEnvelope.Body?
}
