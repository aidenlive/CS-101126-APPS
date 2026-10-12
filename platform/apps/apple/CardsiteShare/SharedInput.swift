import Foundation
import CoreTransferable
import UniformTypeIdentifiers
import CardsiteKit

/// Finds the web address in what another app shared: a URL attachment
/// (Safari, most apps), else the first web address in shared text.
@MainActor
enum SharedInput {
    static func firstWebURL(in items: [NSExtensionItem]) async -> URL? {
        let providers = items.flatMap { $0.attachments ?? [] }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await load(URL.self, from: provider),
               let web = Destination.normalized(url.absoluteString) {
                return web
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = await load(String.self, from: provider), let web = firstWebURL(inText: text) {
                return web
            }
        }
        for item in items {
            if let text = item.attributedContentText?.string, let web = firstWebURL(inText: text) {
                return web
            }
        }
        return nil
    }

    /// The first http(s) address in `text`, including bare domains
    /// ("example.com/menu"), normalised the way the link editor does.
    nonisolated static func firstWebURL(inText text: String) -> URL? {
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, options: [], range: range) {
                if let url = match.url, let web = Destination.normalized(url.absoluteString) {
                    return web
                }
            }
        }
        return Destination.normalized(text)
    }

    private static func load<T: Transferable & Sendable>(_ type: T.Type, from provider: NSItemProvider) async -> T? {
        await withCheckedContinuation { continuation in
            _ = provider.loadTransferable(type: type) { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }
}
