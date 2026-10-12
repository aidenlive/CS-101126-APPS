import Foundation
import Observation
import CardsiteKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The share extension's one screen: find the address, shorten it with an
/// optional custom address, then copy the short link.
@MainActor
@Observable
final class ShareModel {
    enum Phase: Equatable {
        /// Reading what was shared.
        case reading
        /// No session in the shared Keychain, or the token expired.
        case signedOut
        /// Nothing shared was a web address.
        case noLink
        /// The address is known: optional custom address, then Shorten.
        case editing
        case created(url: URL, address: String)
    }

    private(set) var phase: Phase = .reading
    private(set) var destination: URL?
    /// Off: Cardsite picks a random address, as the link editor's default does.
    var usesCustomAddress = false {
        didSet { slugError = nil }
    }
    var slug = "" {
        didSet { slugError = nil }
    }
    private(set) var slugError: String?
    private(set) var errorMessage: String?
    private(set) var isCreating = false
    private(set) var didCopy = false
    /// The extension couldn't open the app (iOS share extensions may not).
    private(set) var couldNotOpenApp = false

    /// Wired by `ShareViewController` to the extension context.
    var onComplete: () -> Void = {}
    var onCancel: () -> Void = {}
    var openURL: @MainActor (URL) async -> Bool = { _ in false }

    private let session: SessionSnapshot?

    init(session: SessionSnapshot?) {
        self.session = session
    }

    /// `card.site`, for the custom address prefix.
    var publicHost: String { session?.context.publicHost ?? "card.site" }

    func start(with items: [NSExtensionItem]) async {
        let found = await SharedInput.firstWebURL(in: items)
        destination = found
        if session == nil {
            phase = .signedOut
        } else {
            phase = found == nil ? .noLink : .editing
        }
    }

    func shorten() async {
        guard let destination, let session, !isCreating else { return }
        let custom = usesCustomAddress ? slug.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if usesCustomAddress {
            if let problem = Slug.problem(with: custom) {
                slugError = Slug.message(for: problem)
                return
            }
        }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        let client = await session.makeClient(userAgent: Self.userAgent)
        do {
            let link = try await Self.create(with: client, slug: custom, destination: destination)
            let addresses = session.context.addresses
            guard let url = addresses.url(for: link.slug) else {
                errorMessage = String(localized: "The link was created, but its address couldn't be read. Open Cardsite to copy it.")
                return
            }
            phase = .created(url: url, address: addresses.display(for: link.slug))
        } catch let error as APIError {
            switch error {
            case .sessionExpired:
                phase = .signedOut
            case .conflict where !custom.isEmpty:
                slugError = error.localizedDescription
            default:
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyLink() {
        guard case .created(let url, _) = phase else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = url.absoluteString
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #endif
        didCopy = true
    }

    /// Opens Cardsite, carrying the shared address so the app can offer
    /// to shorten it once the user has signed in.
    func openCardsite() async {
        let link = destination.map { CardsiteDeepLink.createLink(destination: $0) } ?? .home
        if await openURL(link.url) {
            onComplete()
        } else {
            couldNotOpenApp = true
        }
    }

    // MARK: Helpers

    /// A custom address is tried once; a random one is drawn again if the
    /// first is taken (409).
    private static func create(with client: APIClient, slug: String, destination: URL) async throws -> Resource {
        guard slug.isEmpty else {
            return try await client.createLink(slug: slug, destination: destination)
        }
        do {
            return try await client.createLink(slug: Slug.random(), destination: destination)
        } catch APIError.conflict {
            return try await client.createLink(slug: Slug.random(), destination: destination)
        }
    }

    private static var userAgent: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        #if os(macOS)
        let platform = "macOS"
        #else
        let platform = "iOS"
        #endif
        return "Cardsite-Apple/\(version) (\(build); \(platform); CardsiteShare)"
    }

    #if DEBUG
    /// For previews: a model already in `phase`, with no network.
    static func preview(_ phase: Phase, destination: URL? = URL(string: "https://example.com/spring/menu")) -> ShareModel {
        let context = SessionContext(baseURL: URL(string: "http://localhost:8080")!, publicHost: "card.site", workspaceID: nil)
        let model = ShareModel(session: phase == .signedOut ? nil : SessionSnapshot(token: "preview", context: context))
        model.destination = destination
        model.phase = phase
        return model
    }
    #endif
}
