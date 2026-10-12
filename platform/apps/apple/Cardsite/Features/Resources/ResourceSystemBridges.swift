import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import CardsiteKit
#if os(iOS)
import UIKit
import Contacts
import ContactsUI
import EventKit
import EventKitUI
#endif

/*
 Files and system sheets for vCards and events.

 · RemoteVCardFile / RemoteCalendarFile: the server's `.vcf` and `.ics` as
   Transferables that fetch when the share sheet or save panel asks for the
   bytes, so ShareLink and fileExporter take them directly.
 · iOS: NewContactView (CNContactViewController for a new contact) and
   EventEditView (EKEventEditViewController). Both run the system's own UI
   out of process: the person confirms the save there, and the app never
   asks for Contacts or Calendars access.
 */

/// `GET /vcards/{id}/download`, the card as the server builds it.
struct RemoteVCardFile: Transferable, Sendable {
    let client: APIClient
    let id: Int
    let filename: String

    init(client: APIClient, id: Int, name: String) {
        self.client = client
        self.id = id
        self.filename = ResourceFileName.make(name, fallback: "contact") + ".vcf"
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .vCard) { file in
            try await file.client.vcardFile(id: file.id)
        }
        .suggestedFileName { $0.filename }
    }
}

/// `GET /api/public/events/{slug}/ics`, the public calendar file.
struct RemoteCalendarFile: Transferable, Sendable {
    let client: APIClient
    let slug: String
    let filename: String

    static let contentType = UTType(filenameExtension: "ics", conformingTo: .calendarEvent) ?? .calendarEvent

    init(client: APIClient, slug: String, name: String) {
        self.client = client
        self.slug = slug
        self.filename = ResourceFileName.make(name, fallback: slug) + ".ics"
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: contentType) { file in
            try await file.client.eventCalendarFile(slug: file.slug)
        }
        .suggestedFileName { $0.filename }
    }
}

/// A file name from a person's or event's name: letters, digits, `-` and `_`.
enum ResourceFileName {
    static func make(_ name: String, fallback: String) -> String {
        var result = ""
        for character in name.trimmingCharacters(in: .whitespacesAndNewlines) {
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                result.append(character)
            } else if character == " ", result.last != "_" {
                result.append("_")
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? fallback : trimmed
    }
}

#if os(iOS)

// MARK: - Contacts

/// A new contact built from a saved vCard: names, organisation, phones,
/// email, website and socials, postal address and birthday. The note is
/// left out: writing it needs an entitlement the app doesn't hold.
enum ContactBuilder {
    static func contact(from card: VCardSettings) -> CNContact {
        let contact = CNMutableContact()
        contact.givenName = card.firstName
        contact.familyName = card.lastName
        contact.organizationName = card.company
        contact.jobTitle = card.jobTitle

        contact.phoneNumbers = card.phoneNumbers
            .filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { CNLabeledValue(label: $0.label.isEmpty ? CNLabelPhoneNumberMobile : $0.label,
                                  value: CNPhoneNumber(stringValue: $0.value)) }

        let email = card.email.trimmingCharacters(in: .whitespaces)
        if !email.isEmpty {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email as NSString)]
        }

        var urls: [CNLabeledValue<NSString>] = []
        let website = card.website.trimmingCharacters(in: .whitespaces)
        if !website.isEmpty {
            urls.append(CNLabeledValue(label: CNLabelURLAddressHomePage, value: website as NSString))
        }
        for social in card.socials where !social.value.trimmingCharacters(in: .whitespaces).isEmpty {
            urls.append(CNLabeledValue(label: social.label.isEmpty ? CNLabelOther : social.label,
                                       value: social.value as NSString))
        }
        contact.urlAddresses = urls

        if [card.street, card.city, card.region, card.zip, card.country].contains(where: { !$0.isEmpty }) {
            let postal = CNMutablePostalAddress()
            postal.street = card.street
            postal.city = card.city
            postal.state = card.region
            postal.postalCode = card.zip
            postal.country = card.country
            contact.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: postal as CNPostalAddress)]
        }

        if let birthday = VCardBirthday.date(from: card.birthday) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = VCardBirthday.zone
            contact.birthday = calendar.dateComponents([.year, .month, .day], from: birthday)
        }

        return (contact.copy() as? CNContact) ?? contact
    }
}

/// The system's new-contact card, in its own navigation controller.
struct NewContactView: UIViewControllerRepresentable {
    let contact: CNContact
    let onDone: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = CNContactViewController(forNewContact: contact)
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, @preconcurrency CNContactViewControllerDelegate {
        let onDone: @MainActor () -> Void

        init(onDone: @escaping @MainActor () -> Void) {
            self.onDone = onDone
        }

        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            onDone()
        }
    }
}

// MARK: - Calendar

/// The system's event editor, filled from a saved event. Start, end and
/// alerts are the author's wall clock in the event's own zone.
struct EventEditView: UIViewControllerRepresentable {
    let settings: EventSettings
    let onDone: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = context.coordinator.store
        let event = EKEvent(eventStore: store)
        let name = settings.name.trimmingCharacters(in: .whitespaces)
        event.title = name.isEmpty ? String(localized: "Event") : name
        let location = settings.location.trimmingCharacters(in: .whitespaces)
        if !location.isEmpty { event.location = location }
        let note = settings.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { event.notes = note }
        if let url = Destination.normalized(settings.url) { event.url = url }
        if let zone = TimeZone(identifier: settings.timezone) { event.timeZone = zone }
        let start = settings.startDate ?? Date.now
        event.startDate = start
        event.endDate = max(settings.endDate ?? start.addingTimeInterval(3_600), start)
        for alert in [settings.firstAlert, settings.secondAlert] {
            if let date = EventWallClock.date(from: alert, timezone: settings.timezone) {
                event.addAlarm(EKAlarm(absoluteDate: date))
            }
        }

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, @preconcurrency EKEventEditViewDelegate {
        let store = EKEventStore()
        let onDone: @MainActor () -> Void

        init(onDone: @escaping @MainActor () -> Void) {
            self.onDone = onDone
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}

#endif
