import Foundation
import AppIntents
import CardsiteKit

/*
 Compiled into the app AND the widget extension (project.yml adds
 Cardsite/Intents/Shared to CardsiteWidgets), so nothing in this folder
 may use app-only code (`AppModel`, `Shared/`, the features).

 Intents and entity queries call the API as the signed-in user through
 `SharedSession`: the token from the shared Keychain group, the base URL
 and workspace from the App Group. That works the same whether the
 system runs them in the app's process or in the widget extension.
 */

/// A signed-in API client for an intent, a query or a widget timeline.
struct IntentSession: Sendable {
    let client: APIClient
    let context: SessionContext
    let shared: SharedSession

    var addresses: AddressBook { context.addresses }

    /// Opens the session the app published, or throws
    /// ``CardsiteIntentError/signedOut``.
    static func open() async throws -> IntentSession {
        guard let shared = SharedSession.current, let snapshot = shared.snapshot() else {
            throw CardsiteIntentError.signedOut
        }
        return IntentSession(client: await snapshot.makeClient(userAgent: userAgent),
                             context: snapshot.context, shared: shared)
    }

    /// `Cardsite-Apple/1.0.0 (1; iOS; CardsiteWidgets)`, so server logs can
    /// tell the app from its extensions.
    static var userAgent: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        let name = info["CFBundleName"] as? String ?? "Cardsite"
        #if os(macOS)
        let platform = "macOS"
        #elseif os(visionOS)
        let platform = "visionOS"
        #else
        let platform = "iOS"
        #endif
        return "Cardsite-Apple/\(version) (\(build); \(platform); \(name))"
    }

    /// Runs `work`, turning API failures into messages Siri and Shortcuts
    /// can speak.
    func run<T: Sendable>(_ work: @Sendable (APIClient) async throws -> T) async throws -> T {
        do {
            return try await work(client)
        } catch {
            throw CardsiteIntentError(error)
        }
    }
}

/// Failures an intent reports to the person, in the app's own words.
enum CardsiteIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// No session in the shared Keychain, or the 7-day token expired.
    case signedOut
    /// The link or QR code was deleted, or belongs to another workspace.
    case notFound
    case message(String)

    init(_ error: Error) {
        if let error = error as? CardsiteIntentError {
            self = error
        } else if let error = error as? APIError {
            self = error == .sessionExpired ? .signedOut : .message(error.localizedDescription)
        } else {
            self = .message(error.localizedDescription)
        }
    }

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signedOut:
            return "Sign in to Cardsite first."
        case .notFound:
            return "That item isn’t in your Cardsite workspace any more."
        case .message(let text):
            return "\(text)"
        }
    }
}
