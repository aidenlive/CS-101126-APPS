import Foundation
import CardsiteKit

/// Everything the link editor edits, as one value. Two copies (the saved one
/// and the edited one) make "unsaved changes" a plain comparison, the way the
/// web compares `linkFormFromLink(link)` with the form (lib/linkForm.ts).
struct LinkForm: Equatable {
    enum Field: Hashable {
        case slug, destination, schedule, targeting, password, clicksLimit, expirationURL
    }

    var slug: String
    var destination: String
    var domainID: Int?
    var projectID: Int?
    var splashPageID: Int?
    var settings: LinkSettings
    var password: PasswordChange = .keep
    /// The click limit as typed; "" is no limit.
    var clicksLimitText: String
    var displayRules: DisplayRules
    var timezone: String
    var isScheduled: Bool
    var start: Date
    var end: Date

    /// Whether the saved link has a schedule. The server can move one but
    /// not clear it, so the switch stays on once it is saved.
    let hasSavedSchedule: Bool

    init(detail: LinkDetail, now: Date = .now) {
        slug = detail.slug
        destination = detail.destination ?? ""
        domainID = detail.domainID
        projectID = detail.projectID
        splashPageID = detail.splashPageID
        settings = detail.settings
        clicksLimitText = detail.settings.clicksLimit.map(String.init) ?? ""
        displayRules = detail.displayRules
        timezone = detail.timezone
        hasSavedSchedule = detail.scheduledAt != nil || detail.scheduledEnd != nil
        isScheduled = hasSavedSchedule
        // Unscheduled links get a sensible starting window for the pickers;
        // it is only sent once the switch is turned on.
        let start = detail.scheduledAt ?? Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        self.start = start
        end = max(detail.scheduledEnd ?? start.addingTimeInterval(7 * 86_400), start)
    }

    // MARK: Validation

    /// Problems to show inline, by field. Empty means the form can be sent.
    func validate() -> [Field: String] {
        var errors: [Field: String] = [:]
        if slug.trimmingCharacters(in: .whitespaces).isEmpty {
            errors[.slug] = String(localized: "An address is required")
        } else if let problem = Slug.problem(with: slug) {
            errors[.slug] = Slug.message(for: problem)
        }
        if Destination.normalized(destination) == nil {
            errors[.destination] = String(localized: "Enter a web address starting with https:// or a domain like example.com.")
        }
        if isScheduled, end < start {
            errors[.schedule] = String(localized: "The end can’t be before the start.")
        }
        let limit = clicksLimitText.trimmingCharacters(in: .whitespaces)
        if !limit.isEmpty, (Int(limit) ?? 0) <= 0 {
            errors[.clicksLimit] = String(localized: "Enter a whole number above 0, or leave it empty for no limit.")
        }
        let expiration = settings.expirationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !expiration.isEmpty, Destination.normalized(expiration) == nil {
            errors[.expirationURL] = String(localized: "Enter a web address starting with https:// or a domain like example.com.")
        }
        if case .set(let value) = password, value.trimmingCharacters(in: .whitespaces).isEmpty {
            errors[.password] = String(localized: "A password can’t be only spaces.")
        }
        return errors
    }

    // MARK: Request

    /// The save request. Call only after ``validate()`` came back empty.
    ///
    /// - Parameter saved: the form as last saved; targeting is sent only when
    ///   it changed, so an untouched link never meets the targeting gate.
    func changes(comparedWith saved: LinkForm) -> LinkChanges {
        var settings = self.settings
        let limit = clicksLimitText.trimmingCharacters(in: .whitespaces)
        settings.clicksLimit = limit.isEmpty ? nil : Int(limit)
        let expiration = settings.expirationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.expirationURL = expiration.isEmpty ? "" : (Destination.normalized(expiration)?.absoluteString ?? expiration)
        return LinkChanges(
            slug: slug.trimmingCharacters(in: .whitespaces),
            destination: Destination.normalized(destination)?.absoluteString ?? destination,
            domainID: domainID,
            projectID: projectID,
            splashPageID: splashPageID,
            settings: settings,
            password: password,
            displayRules: displayRules == saved.displayRules ? nil : displayRules,
            timezone: timezone,
            scheduledAt: isScheduled ? start : nil,
            scheduledEnd: isScheduled ? end : nil
        )
    }
}

extension LinkForm.Field {
    /// Where a server refusal belongs, from its readable message.
    static func owning(_ error: APIError) -> LinkForm.Field? {
        switch error {
        case .conflict:
            return .slug
        case .planCapability(let label):
            let name = (label ?? "").lowercased()
            if name.contains("target") { return .targeting }
            if name.contains("password") { return .password }
            return nil
        case .invalid(let message):
            let text = message.lowercased()
            if text.contains("url is required") || text.contains("address") { return .slug }
            return nil
        default:
            return nil
        }
    }
}
