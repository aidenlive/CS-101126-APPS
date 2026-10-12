import SwiftUI
import CardsiteKit

/// Sample data for `#Preview`s: images from the live fixtures
/// (ContractTests/fixtures/08a and 23b) and the 28 types from 23a.
@MainActor
enum QRCodesPreviewData {
    static let app = AppModel(configuration: .preview)

    /// Black on white, from 08a.
    static let blackPNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAQAAAAEAAQMAAABmvDolAAAABlBMVEX///8AAABVwtN+AAABYElEQVR42uyYsZHFIAxE10NA6BIohdauNEqhBEICj/dGAs//vu9/BUhs4MDzIg3alYSlpaWl/0TVASCSDXtN48+PLeCUTziA2LGTrKnKn+wO2MgjHIFdiAYkKVVxC3RACtW8A6TWaa9GgdEXoY/GkDo8No51YPpk6LHHtrevRmodmNK+gABf0tE6II0zchOxyVcLVawB24mNB0KP7DMNKpCLN2B0hcQixniAVHPJ98bxAGhgXIXaWRPr3Sd9ABt56riIyLazJdZU8ptP2gCmO0gcqBHO9/CnL+wDYzzgMZekpj753hdugO28rUkjLbI7YDulToEyNw+r5Pt7MQJcUxC7vAiJAyQWuANeRxKpUtMt6cMnHQDXlqSFkm1RC/Xhk/aB19Yc2+UP+XmtNgD08SJ0PLjfBn0B8lNjUUbB5yuKbeC6kWosjrGYBe6A60jCOS/OGwmNAUtLSx71GwAA//8aI2n9uKrKdwAAAABJRU5ErkJggg=="
    /// #112233 on white, from 23b.
    static let inkPNG = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAQAAAAEAAQMAAABmvDolAAAABlBMVEX///8RIjNQRD0PAAABYElEQVR42uyYsZHFIAxE10NA6BIohdauNEqhBEICj/dGAs//vu9/BUhs4MDzIg3alYSlpaWl/0TVASCSDXtN48+PLeCUTziA2LGTrKnKn+wO2MgjHIFdiAYkKVVxC3RACtW8A6TWaa9GgdEXoY/GkDo8No51YPpk6LHHtrevRmodmNK+gABf0tE6II0zchOxyVcLVawB24mNB0KP7DMNKpCLN2B0hcQixniAVHPJ98bxAGhgXIXaWRPr3Sd9ABt56riIyLazJdZU8ptP2gCmO0gcqBHO9/CnL+wDYzzgMZekpj753hdugO28rUkjLbI7YDulToEyNw+r5Pt7MQJcUxC7vAiJAyQWuANeRxKpUtMt6cMnHQDXlqSFkm1RC/Xhk/aB19Yc2+UP+XmtNgD08SJ0PLjfBn0B8lNjUUbB5yuKbeC6kWosjrGYBe6A60jCOS/OGwmNAUtLSx71GwAA//8aI2n9uKrKdwAAAABJRU5ErkJggg=="

    static let codes: [QRCode] = [
        QRCode(id: 1, name: "Window menu", type: "url", imageDataURL: blackPNG,
               embeddedData: "https://example.com/menu", createdAt: Date.now.addingTimeInterval(-86_400 * 3)),
        QRCode(id: 2, name: "Studio WiFi", type: "wifi", imageDataURL: inkPNG,
               embeddedData: "WIFI:T:WPA;S:Studio;P:correct-horse;H:false;;", createdAt: Date.now.addingTimeInterval(-86_400 * 9)),
        QRCode(id: 3, name: "Spring open day", type: "event", imageDataURL: blackPNG,
               embeddedData: "BEGIN:VEVENT\nSUMMARY:Spring open day\nEND:VEVENT", createdAt: Date.now.addingTimeInterval(-86_400 * 20)),
        QRCode(id: 4, name: "Tip jar", type: "paypal", imageDataURL: inkPNG,
               embeddedData: "https://www.paypal.com/cgi-bin/webscr?cmd=_donations", createdAt: Date.now.addingTimeInterval(-86_400 * 41)),
        QRCode(id: 5, name: "Reception contact card", type: "vcard", imageDataURL: blackPNG,
               embeddedData: "BEGIN:VCARD\nVERSION:3.0\nEND:VCARD", createdAt: Date.now.addingTimeInterval(-86_400 * 60)),
    ]

    static let types: [QRCodeTypeInfo] = [
        QRCodeTypeInfo(value: "url", label: "URL", group: "web"),
        QRCodeTypeInfo(value: "url_dynamic", label: "Dynamic URL", group: "web"),
        QRCodeTypeInfo(value: "text", label: "Text", group: "basic"),
        QRCodeTypeInfo(value: "email", label: "Email", group: "contact"),
        QRCodeTypeInfo(value: "phone", label: "Phone", group: "contact"),
        QRCodeTypeInfo(value: "sms", label: "SMS", group: "contact"),
        QRCodeTypeInfo(value: "whatsapp", label: "WhatsApp", group: "messaging"),
        QRCodeTypeInfo(value: "viber", label: "Viber", group: "messaging"),
        QRCodeTypeInfo(value: "signal", label: "Signal", group: "messaging"),
        QRCodeTypeInfo(value: "skype", label: "Skype", group: "messaging"),
        QRCodeTypeInfo(value: "facetime", label: "FaceTime", group: "messaging"),
        QRCodeTypeInfo(value: "zoom", label: "Zoom", group: "messaging"),
        QRCodeTypeInfo(value: "vcard", label: "vCard", group: "contact"),
        QRCodeTypeInfo(value: "mecard", label: "MeCard", group: "contact"),
        QRCodeTypeInfo(value: "wifi", label: "WiFi", group: "network"),
        QRCodeTypeInfo(value: "location", label: "Location", group: "location"),
        QRCodeTypeInfo(value: "event", label: "Event", group: "calendar"),
        QRCodeTypeInfo(value: "crypto", label: "Crypto", group: "payment"),
        QRCodeTypeInfo(value: "bitcoin", label: "Bitcoin", group: "payment"),
        QRCodeTypeInfo(value: "ethereum", label: "Ethereum", group: "payment"),
        QRCodeTypeInfo(value: "litecoin", label: "Litecoin", group: "payment"),
        QRCodeTypeInfo(value: "paypal", label: "PayPal", group: "payment"),
        QRCodeTypeInfo(value: "upi", label: "UPI", group: "payment"),
        QRCodeTypeInfo(value: "epc", label: "EPC / SEPA", group: "payment"),
        QRCodeTypeInfo(value: "pix", label: "PIX", group: "payment"),
        QRCodeTypeInfo(value: "app_store", label: "App Store", group: "app"),
        QRCodeTypeInfo(value: "play_store", label: "Play Store", group: "app"),
        QRCodeTypeInfo(value: "information", label: "Information", group: "basic"),
    ]

    /// A model whose list serves `codes`, or fails with `failing`.
    static func model(codes items: [QRCode] = QRCodesPreviewData.codes, failing: APIError? = nil) -> QRCodesModel {
        QRCodesModel(client: app.client, types: types) { page in
            if let failing { throw failing }
            return Page(items: page == 1 ? items : [], meta: PageMeta(page: page, perPage: 50, total: items.count))
        }
    }
}
