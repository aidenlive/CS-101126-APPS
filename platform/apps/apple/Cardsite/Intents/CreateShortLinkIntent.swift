import Foundation
import AppIntents
import CardsiteKit

/// "Shorten a link with Cardsite": creates a short link and copies it.
///
/// App target only (it uses `Pasteboard` from Shared/Platform.swift).
struct CreateShortLinkIntent: AppIntent {
    static var title: LocalizedStringResource { "Create Short Link" }
    static var description: IntentDescription? {
        IntentDescription(
            "Shortens a web address with Cardsite and copies the short link to the clipboard.",
            categoryName: "Links"
        )
    }

    @Parameter(title: "Destination", description: "The web address the short link opens.")
    var destination: URL

    @Parameter(title: "Custom Address",
               description: "Optional. Letters, numbers, hyphens and underscores. Left empty, Cardsite picks one.")
    var slug: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Shorten \(\.$destination)") {
            \.$slug
        }
    }

    init() {}

    init(destination: URL, slug: String? = nil) {
        self.destination = destination
        self.slug = slug
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<URL> & ProvidesDialog {
        guard let target = Destination.normalized(destination.absoluteString) else {
            throw CardsiteIntentError.message(String(localized: "Enter a web address starting with https:// or a domain like example.com."))
        }
        let custom = (slug ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty, let problem = Slug.problem(with: custom) {
            throw CardsiteIntentError.message(Slug.message(for: problem))
        }

        let session = try await IntentSession.open()
        let link = try await session.run { client in
            try await Self.create(with: client, slug: custom, destination: target)
        }
        guard let shortURL = session.addresses.url(for: link.slug) else {
            throw CardsiteIntentError.message(String(localized: "The link was created, but its address couldn’t be read. Open Cardsite to copy it."))
        }

        Pasteboard.copy(shortURL.absoluteString)
        let address = session.addresses.display(for: link.slug)
        return .result(value: shortURL, dialog: IntentDialog("\(address) is ready and copied."))
    }

    /// A custom address is tried once; a random one is drawn again if the
    /// first is taken (409), as the editor's dice would.
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
}
