import Foundation
import CardsiteKit

/// QR code images kept in the App Group container, so the "My QR code"
/// widget and Siri can show a code without the network, and the app's
/// intents and the widget extension share one copy.
///
/// Files are `QRCodes/<workspace>-<id>.png`, `personal` standing in for
/// the default workspace, so two workspaces' code 12 never collide. The
/// server renders the image (`qr_code`, a PNG data URL) on every list row
/// and full record.
enum QRImageCache {
    static func cached(id: Int, in session: IntentSession) -> Data? {
        guard let url = fileURL(id: id, session: session) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func store(_ png: Data, for id: Int, in session: IntentSession) {
        guard let url = fileURL(id: id, session: session) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
        } catch {
            // A cache: the next read goes to the network.
        }
    }

    /// The code's image, fresh from the server when it can be reached and
    /// from the cache when it can't. Also returns the code, when it was
    /// fetched, so a caller can show its current name.
    static func image(for id: Int, in session: IntentSession) async throws -> (png: Data, design: QRCodeDesign?) {
        let design: QRCodeDesign
        do {
            design = try await session.client.qrCodeDesign(id: id)
        } catch APIError.invalid {
            // 404: deleted, or in another workspace. A cached copy would
            // show a code that no longer exists.
            throw CardsiteIntentError.notFound
        } catch APIError.sessionExpired {
            throw CardsiteIntentError.signedOut
        } catch {
            // Offline or the server failed: the last copy still scans.
            if let png = cached(id: id, in: session) { return (png, nil) }
            throw CardsiteIntentError(error)
        }
        if let png = design.pngData {
            store(png, for: id, in: session)
            return (png, design)
        }
        if let png = cached(id: id, in: session) { return (png, design) }
        throw CardsiteIntentError.message(String(localized: "This QR code has no image yet. Open it in Cardsite to render it."))
    }

    private static func fileURL(id: Int, session: IntentSession) -> URL? {
        let scope = session.context.workspaceID.map(String.init) ?? "personal"
        return session.shared.containerURL?
            .appendingPathComponent("QRCodes", isDirectory: true)
            .appendingPathComponent("\(scope)-\(id).png", isDirectory: false)
    }
}
