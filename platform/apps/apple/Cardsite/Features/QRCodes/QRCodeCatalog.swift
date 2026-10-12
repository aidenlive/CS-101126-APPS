import Foundation
import CardsiteKit

/// The builder's per-type fields, key for key what the web builder
/// (apps/web/src/pages/qrcodes/QrCodeBuilderPage.tsx, `renderTypeFields`)
/// writes into `settings`, and what the generator
/// (apps/api/internal/services/qrcode.go, `buildEmbeddedData`) reads.
///
/// Every value is a string, as the web sends them: numbers included
/// (the generator accepts either) and the WiFi hidden flag as "true"/"false".
struct QRField: Identifiable, Hashable, Sendable {
    enum Entry: Hashable, Sendable {
        /// Free text with sentence capitalisation.
        case words
        /// A name: word capitalisation, name autofill.
        case personName(PersonPart)
        /// Codes, IDs, addresses: no capitalisation or autocorrection.
        case code
        case email
        case phone
        case url
        /// Digits and one decimal point; a comma becomes a point.
        case decimal
        /// Like `decimal`, but negative values allowed (latitude, longitude).
        case signedDecimal
    }

    enum PersonPart: Hashable, Sendable { case given, family }

    enum Kind: Hashable, Sendable {
        case text(Entry)
        case multiline(lines: Int)
        case choice([Option])
        /// Stored as "true" / "false".
        case toggle
        /// Floating local time, `YYYY-MM-DDTHH:mm`, or "" when unset.
        case dateTime
    }

    struct Option: Hashable, Sendable, Identifiable {
        let value: String
        let label: String
        var id: String { value }
    }

    let key: String
    let label: String
    var kind: Kind = .text(.words)
    var placeholder: String = ""
    /// Shown and sent when the key is absent, so what the control shows is
    /// what gets encoded.
    var defaultValue: String?
    var maxLength: Int?
    var help: String?

    var id: String { key }

    /// Whether a non-empty value means the user has entered something to
    /// encode. Choices and toggles always have a value, so they don't count.
    var countsAsContent: Bool {
        switch kind {
        case .choice, .toggle: return false
        case .text, .multiline, .dateTime: return defaultValue == nil
        }
    }

    var isNumeric: Bool {
        if case .text(let entry) = kind { return entry == .decimal || entry == .signedDecimal }
        return false
    }
}

/// A titled run of fields. Most types have one untitled group.
struct QRFieldGroup: Identifiable, Hashable, Sendable {
    let title: String?
    let fields: [QRField]
    var id: String { title ?? fields.first?.key ?? "fields" }
}

enum QRCodeCatalog {
    /// The type `url_dynamic` encodes one of the user's short links, chosen
    /// from a picker, so its destination can change after printing.
    static let dynamicURLType = "url_dynamic"
    static let defaultType = "url"

    /// The groups of fields for a server type. Unknown types fall back to the
    /// generator's default: a single `data` field.
    static func groups(for type: String) -> [QRFieldGroup] {
        func one(_ fields: QRField...) -> [QRFieldGroup] { [QRFieldGroup(title: nil, fields: fields)] }

        let phone = QRField(key: "phone", label: String(localized: "Phone Number"), kind: .text(.phone), placeholder: "+1234567890")
        let urlField = QRField(key: "url", label: String(localized: "URL"), kind: .text(.url), placeholder: "https://example.com")
        let firstName = QRField(key: "first_name", label: String(localized: "First Name"), kind: .text(.personName(.given)))
        let lastName = QRField(key: "last_name", label: String(localized: "Last Name"), kind: .text(.personName(.family)))
        let amountOptional = QRField(key: "amount", label: String(localized: "Amount (optional)"), kind: .text(.decimal))
        let payeeName = QRField(key: "payee_name", label: String(localized: "Payee Name"), kind: .text(.words))

        switch type {
        case "text":
            return one(QRField(key: "text", label: String(localized: "Text"), kind: .multiline(lines: 4),
                               placeholder: String(localized: "Enter your text…"), maxLength: 3000))

        case "url":
            return one(urlField)

        case dynamicURLType:
            // The link picker writes `url` (and `link_id`); see QRCodeBuilderModel.
            return []

        case "phone":
            return one(phone)

        case "sms":
            return one(phone,
                       QRField(key: "body", label: String(localized: "Message"), kind: .multiline(lines: 2),
                               placeholder: String(localized: "SMS message…"), maxLength: 160))

        case "email":
            return one(QRField(key: "email", label: String(localized: "Email Address"), kind: .text(.email), placeholder: "user@example.com"),
                       QRField(key: "subject", label: String(localized: "Subject"), placeholder: String(localized: "Email subject")),
                       QRField(key: "body", label: String(localized: "Body"), kind: .multiline(lines: 3),
                               placeholder: String(localized: "Email body…")))

        case "whatsapp":
            return one(QRField(key: "phone", label: String(localized: "Phone Number"), kind: .text(.phone),
                               placeholder: String(localized: "1234567890 (no + or spaces)")),
                       QRField(key: "body", label: String(localized: "Message"), kind: .multiline(lines: 3),
                               placeholder: String(localized: "Pre-filled message…")))

        case "viber":
            return one(phone,
                       QRField(key: "body", label: String(localized: "Message (optional)"), kind: .multiline(lines: 2)))

        case "signal":
            return one(phone)

        case "skype":
            return one(QRField(key: "username", label: String(localized: "Skype Username"), kind: .text(.code),
                               placeholder: String(localized: "username")),
                       QRField(key: "action", label: String(localized: "Action"), kind: .choice([
                           .init(value: "call", label: String(localized: "Call")),
                           .init(value: "chat", label: String(localized: "Chat")),
                       ]), defaultValue: "call"))

        case "facetime":
            return one(QRField(key: "phone", label: String(localized: "Phone / Email"), kind: .text(.code),
                               placeholder: String(localized: "+1234567890 or email")))

        case "zoom":
            return one(QRField(key: "meeting_url", label: String(localized: "Meeting URL (or fill ID below)"), kind: .text(.url),
                               placeholder: "https://zoom.us/j/…"),
                       QRField(key: "meeting_id", label: String(localized: "Meeting ID"), kind: .text(.code), placeholder: "123 456 7890"),
                       QRField(key: "password", label: String(localized: "Password (optional)"), kind: .text(.code)))

        case "mecard":
            return [
                QRFieldGroup(title: String(localized: "Name"), fields: [firstName, lastName]),
                QRFieldGroup(title: String(localized: "Contact"), fields: [
                    QRField(key: "phone", label: String(localized: "Phone"), kind: .text(.phone)),
                    QRField(key: "email", label: String(localized: "Email"), kind: .text(.email)),
                    QRField(key: "website", label: String(localized: "Website"), kind: .text(.url)),
                    QRField(key: "address", label: String(localized: "Address")),
                    QRField(key: "note", label: String(localized: "Note"), kind: .multiline(lines: 2)),
                ]),
            ]

        case "wifi":
            return one(QRField(key: "ssid", label: String(localized: "Network Name (SSID)"), kind: .text(.code),
                               placeholder: String(localized: "WiFi network name")),
                       QRField(key: "password", label: String(localized: "Password"), kind: .text(.code)),
                       QRField(key: "encryption", label: String(localized: "Encryption"), kind: .choice([
                           .init(value: "WPA", label: "WPA/WPA2"),
                           .init(value: "WEP", label: "WEP"),
                           .init(value: "nopass", label: String(localized: "None")),
                       ]), defaultValue: "WPA"),
                       QRField(key: "is_hidden", label: String(localized: "Hidden network"), kind: .toggle))

        case "vcard":
            return [
                QRFieldGroup(title: String(localized: "Name"), fields: [firstName, lastName]),
                QRFieldGroup(title: String(localized: "Contact"), fields: [
                    QRField(key: "email", label: String(localized: "Email"), kind: .text(.email)),
                    QRField(key: "phone", label: String(localized: "Phone"), kind: .text(.phone)),
                    QRField(key: "company", label: String(localized: "Company")),
                    QRField(key: "title", label: String(localized: "Job Title")),
                    QRField(key: "website", label: String(localized: "Website"), kind: .text(.url)),
                ]),
                QRFieldGroup(title: String(localized: "Address"), fields: [
                    QRField(key: "street", label: String(localized: "Street")),
                    QRField(key: "city", label: String(localized: "City")),
                    QRField(key: "region", label: String(localized: "Region/State")),
                    QRField(key: "zip", label: String(localized: "ZIP/Postal Code"), kind: .text(.code)),
                    QRField(key: "country", label: String(localized: "Country")),
                ]),
                QRFieldGroup(title: String(localized: "Note"), fields: [
                    QRField(key: "note", label: String(localized: "Note"), kind: .multiline(lines: 2)),
                ]),
            ]

        case "location":
            return one(QRField(key: "latitude", label: String(localized: "Latitude"), kind: .text(.signedDecimal), placeholder: "40.7128"),
                       QRField(key: "longitude", label: String(localized: "Longitude"), kind: .text(.signedDecimal), placeholder: "-74.0060"))

        case "event":
            return one(QRField(key: "title", label: String(localized: "Event Title"), placeholder: String(localized: "Event name")),
                       QRField(key: "location", label: String(localized: "Location")),
                       QRField(key: "start_datetime", label: String(localized: "Start"), kind: .dateTime),
                       QRField(key: "end_datetime", label: String(localized: "End"), kind: .dateTime),
                       QRField(key: "url", label: String(localized: "URL"), kind: .text(.url)),
                       QRField(key: "note", label: String(localized: "Notes"), kind: .multiline(lines: 2)))

        case "bitcoin":
            return one(QRField(key: "address", label: String(localized: "Bitcoin Address"), kind: .text(.code), placeholder: "bc1q…"),
                       amountOptional)

        case "ethereum":
            return one(QRField(key: "address", label: String(localized: "Ethereum Address"), kind: .text(.code), placeholder: "0x…"),
                       QRField(key: "amount", label: String(localized: "Amount (ETH, optional)"), kind: .text(.decimal)))

        case "litecoin":
            return one(QRField(key: "address", label: String(localized: "Litecoin Address"), kind: .text(.code), placeholder: "L…"),
                       amountOptional)

        case "crypto":
            return one(QRField(key: "coin", label: String(localized: "Cryptocurrency"), kind: .choice([
                           .init(value: "bitcoin", label: "Bitcoin"),
                           .init(value: "ethereum", label: "Ethereum"),
                           .init(value: "litecoin", label: "Litecoin"),
                           .init(value: "bitcoincash", label: "Bitcoin Cash"),
                       ]), defaultValue: "bitcoin"),
                       QRField(key: "address", label: String(localized: "Wallet Address"), kind: .text(.code)),
                       amountOptional)

        case "paypal":
            return one(QRField(key: "email", label: String(localized: "PayPal Email"), kind: .text(.email)),
                       QRField(key: "title", label: String(localized: "Item Title")),
                       QRField(key: "currency", label: String(localized: "Currency"),
                               kind: .choice(["USD", "EUR", "GBP", "JPY", "CAD", "AUD"].map { .init(value: $0, label: $0) }),
                               defaultValue: "USD"),
                       QRField(key: "price", label: String(localized: "Price"), kind: .text(.decimal)),
                       QRField(key: "type", label: String(localized: "Payment Type"), kind: .choice([
                           .init(value: "_xclick", label: String(localized: "Buy Now")),
                           .init(value: "_donations", label: String(localized: "Donation")),
                           .init(value: "_cart", label: String(localized: "Add to Cart")),
                       ]), defaultValue: "_xclick"))

        case "upi":
            return one(QRField(key: "payee_id", label: String(localized: "Payee ID (VPA)"), kind: .text(.code), placeholder: "user@upi"),
                       payeeName,
                       QRField(key: "currency", label: String(localized: "Currency"), kind: .text(.code), defaultValue: "INR"),
                       QRField(key: "amount", label: String(localized: "Amount"), kind: .text(.decimal)))

        case "epc":
            return one(payeeName,
                       QRField(key: "iban", label: String(localized: "IBAN"), kind: .text(.code), placeholder: "DE89370400440532013000"),
                       QRField(key: "bic", label: String(localized: "BIC/SWIFT"), kind: .text(.code)),
                       QRField(key: "amount", label: String(localized: "Amount (EUR)"), kind: .text(.decimal)),
                       QRField(key: "reference", label: String(localized: "Reference"), kind: .text(.code)))

        case "pix":
            return one(QRField(key: "payee_key", label: String(localized: "Payee Key (CPF/CNPJ/Email/Phone)"), kind: .text(.code)),
                       payeeName,
                       QRField(key: "city", label: String(localized: "City")),
                       QRField(key: "amount", label: String(localized: "Amount (BRL)"), kind: .text(.decimal)),
                       QRField(key: "transaction_id", label: String(localized: "Transaction ID (optional)"), kind: .text(.code)))

        case "app_store":
            return one(QRField(key: "url", label: String(localized: "App Store URL"), kind: .text(.url),
                               placeholder: "https://apps.apple.com/app/…"))

        case "play_store":
            return one(QRField(key: "url", label: String(localized: "Play Store URL"), kind: .text(.url),
                               placeholder: "https://play.google.com/store/apps/details?id=…"))

        case "information":
            return one(QRField(key: "title", label: String(localized: "Title")),
                       QRField(key: "description", label: String(localized: "Description"), kind: .multiline(lines: 3)),
                       QRField(key: "website", label: String(localized: "Website (optional)"), kind: .text(.url)),
                       QRField(key: "email", label: String(localized: "Email (optional)"), kind: .text(.email)),
                       QRField(key: "phone", label: String(localized: "Phone (optional)"), kind: .text(.phone)))

        default:
            return one(QRField(key: "data", label: String(localized: "Data"), kind: .multiline(lines: 3)))
        }
    }

    static func fields(for type: String) -> [QRField] {
        groups(for: type).flatMap(\.fields)
    }

    /// Group titles, worded as on the web (`qr.group.*`).
    static func groupTitle(_ group: String) -> String {
        switch group {
        case "web": return String(localized: "Web")
        case "basic": return String(localized: "Basic")
        case "contact": return String(localized: "Contact")
        case "messaging": return String(localized: "Messaging")
        case "network": return String(localized: "Network")
        case "location": return String(localized: "Location")
        case "calendar": return String(localized: "Calendar")
        case "payment": return String(localized: "Payment")
        case "app": return String(localized: "App Stores")
        default: return group.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// The server's types grouped in order of each group's first appearance,
    /// as the web groups them.
    static func grouped(_ types: [QRCodeTypeInfo]) -> [(group: String, types: [QRCodeTypeInfo])] {
        var order: [String] = []
        var byGroup: [String: [QRCodeTypeInfo]] = [:]
        for info in types {
            if byGroup[info.group] == nil { order.append(info.group) }
            byGroup[info.group, default: []].append(info)
        }
        return order.map { ($0, byGroup[$0] ?? []) }
    }

    /// A readable label for a type value when the server list isn't loaded.
    static func fallbackLabel(_ type: String) -> String {
        switch type {
        case "url": return "URL"
        case dynamicURLType: return String(localized: "Dynamic URL")
        case "sms": return "SMS"
        case "wifi": return "WiFi"
        case "vcard": return "vCard"
        case "mecard": return "MeCard"
        case "upi": return "UPI"
        case "epc": return "EPC / SEPA"
        case "pix": return "PIX"
        case "paypal": return "PayPal"
        case "facetime": return "FaceTime"
        case "whatsapp": return "WhatsApp"
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// The SF Symbol for a type, used in the picker, the grid and the detail.
    static func symbol(for type: String) -> String {
        switch type {
        case "url": return "link"
        case dynamicURLType: return "arrow.triangle.2.circlepath"
        case "text": return "text.alignleft"
        case "information": return "info.circle"
        case "email": return "envelope"
        case "phone": return "phone"
        case "sms": return "message"
        case "whatsapp", "viber", "signal": return "bubble.left"
        case "skype", "facetime", "zoom": return "video"
        case "vcard": return "person.crop.rectangle"
        case "mecard": return "person.text.rectangle"
        case "wifi": return "wifi"
        case "location": return "mappin.and.ellipse"
        case "event": return "calendar"
        case "crypto", "bitcoin": return "bitcoinsign.circle"
        case "ethereum": return "diamond"
        case "litecoin": return "l.circle"
        case "paypal": return "creditcard"
        case "upi": return "indianrupeesign.circle"
        case "epc": return "eurosign.circle"
        case "pix": return "brazilianrealsign.circle"
        case "app_store": return "arrow.down.app"
        case "play_store": return "play.rectangle"
        default: return "qrcode"
        }
    }

    /// True for types whose encoded content is a web address.
    static func encodesURL(_ type: String) -> Bool {
        ["url", dynamicURLType, "app_store", "play_store"].contains(type)
    }
}

extension JSONValue {
    /// A settings value as the text a field shows. Numbers count, since API
    /// clients may store them as numbers.
    var fieldText: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }
}
