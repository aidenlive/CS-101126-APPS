import Foundation
import AppIntents
import CardsiteKit

/// A stored QR code, as Siri, Shortcuts and the "My QR code" widget see it.
struct QRCodeEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "QR Code")
    }
    static var defaultQuery: QRCodeEntityQuery { QRCodeEntityQuery() }

    let id: Int
    let name: String
    /// What a scan opens: the encoded URL or text.
    let target: String?

    init(id: Int, name: String, target: String?) {
        self.id = id
        self.name = name
        self.target = target
    }

    init(_ code: QRCode) {
        self.init(id: code.id, name: code.name, target: code.target)
    }

    init(_ design: QRCodeDesign) {
        self.init(id: design.id, name: design.name,
                  target: design.settings?["url"]?.stringValue ?? design.embeddedData)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(target ?? "")",
            image: DisplayRepresentation.Image(systemName: "qrcode")
        )
    }
}

struct QRCodeEntityQuery: EntityStringQuery {
    func entities(for identifiers: [QRCodeEntity.ID]) async throws -> [QRCodeEntity] {
        let session = try await IntentSession.open()
        let found = try await session.run { client in
            try await withThrowingTaskGroup(of: QRCodeDesign?.self) { group in
                for id in identifiers {
                    group.addTask {
                        do {
                            return try await client.qrCodeDesign(id: id)
                        } catch APIError.invalid {
                            return nil
                        }
                    }
                }
                var designs: [QRCodeDesign] = []
                for try await design in group {
                    if let design { designs.append(design) }
                }
                return designs
            }
        }
        // The full record carries the image: keep it for the widget.
        for design in found {
            if let png = design.pngData { QRImageCache.store(png, for: design.id, in: session) }
        }
        return identifiers.compactMap { id in found.first { $0.id == id }.map { QRCodeEntity($0) } }
    }

    func entities(matching string: String) async throws -> [QRCodeEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let codes = try await recentCodes()
        guard !needle.isEmpty else { return codes }
        return codes.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
                || ($0.target ?? "").localizedCaseInsensitiveContains(needle)
        }
    }

    func suggestedEntities() async throws -> [QRCodeEntity] {
        // Signed out: nothing to suggest (App Shortcuts refreshes these on
        // every launch, and an error here only fills the console).
        do { return try await recentCodes() } catch CardsiteIntentError.signedOut { return [] }
    }

    /// The first page of QR codes (50). Every row inlines its image, so the
    /// cache is refreshed on the way.
    private func recentCodes() async throws -> [QRCodeEntity] {
        let session = try await IntentSession.open()
        let page = try await session.run { client in try await client.qrCodes(page: 1) }
        for code in page.items {
            if let png = code.pngData { QRImageCache.store(png, for: code.id, in: session) }
        }
        return page.items.map { QRCodeEntity($0) }
    }
}
