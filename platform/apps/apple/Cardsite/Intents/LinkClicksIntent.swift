import Foundation
import AppIntents
import CardsiteKit

/// "How many clicks on card.site/menu?": a link's all-time clicks, as a
/// number Shortcuts can pass on. App target only.
struct LinkClicksIntent: AppIntent {
    static var title: LocalizedStringResource { "Get Link Clicks" }
    static var description: IntentDescription? {
        IntentDescription(
            "Gets how many times one of your short links has been clicked.",
            categoryName: "Links"
        )
    }

    @Parameter(title: "Link")
    var link: LinkEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get clicks on \(\.$link)")
    }

    init() {}

    init(link: LinkEntity) {
        self.link = link
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let session = try await IntentSession.open()
        let id = link.id
        let fresh: Resource
        do {
            fresh = try await session.client.link(id: id)
        } catch APIError.invalid {
            throw CardsiteIntentError.notFound
        } catch {
            throw CardsiteIntentError(error)
        }
        let address = session.addresses.display(for: fresh.slug)
        let count = fresh.clicks.formatted(.number)
        let sentence = fresh.clicks == 1
            ? String(localized: "\(address) has 1 click.")
            : String(localized: "\(address) has \(count) clicks.")
        return .result(value: fresh.clicks, dialog: IntentDialog("\(sentence)"))
    }
}
