import Foundation

/// Every failure the app can show, already classified.
///
/// The server's `error.title` is human-readable for most routes
/// ("That address is already taken"), so it is passed through as the message.
public enum APIError: Error, Sendable, Equatable {
    /// The session token is missing, expired or revoked. The app signs out.
    case sessionExpired
    /// The server refused the credentials sent with this request (wrong
    /// password at sign-in or account deletion). The session stays valid.
    case rejected(String)
    /// The plan's limit for `limit` (e.g. `custom_slugs_limit`) is reached.
    case planLimit(limit: String, current: Int, max: Int)
    /// The plan lacks a capability (`label` is its display name when sent).
    case planCapability(label: String?)
    /// 409: address taken, active subscription, a stale block edit, and
    /// similar. `lastEditor` is `error.last_editor.name`, which the server
    /// sends with a stale block `PUT` (see ``lastEditorName``).
    case conflict(title: String, message: String?, lastEditor: String? = nil)
    /// 400 / 404 / 422 with a readable reason.
    case invalid(String)
    case rateLimited(retryAfter: TimeInterval?)
    case maintenance
    case offline
    case server(status: Int, title: String?)
    case transport(String)
    case decoding(String)
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return String(localized: "Your session has ended. Sign in again to continue.")
        case .rejected(let message):
            return message
        case .planLimit(let limit, _, let max):
            if limit == "custom_slugs_limit" {
                // No call to action toward buying elsewhere: App Review 3.1.1
                // forbids it outside the US storefront.
                if max == 1 {
                    return String(localized: "Your plan includes 1 custom address, and it is in use. Delete it to make room.")
                }
                return String(localized: "Your plan includes \(max) custom addresses, and they are all in use. Delete one to make room.")
            }
            return String(localized: "This would go over your plan's limit (\(max)).")
        case .planCapability(let label):
            if let label {
                return String(localized: "\(label) is not included in your plan.")
            }
            return String(localized: "This feature is not included in your plan.")
        case .conflict(let title, let message, _):
            if title == "active_subscription" {
                return message ?? String(localized: "Cancel your subscription before deleting your account.")
            }
            return message ?? title
        case .invalid(let message):
            return message
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter >= 60 {
                let minutes = Int((retryAfter / 60).rounded(.up))
                return String(localized: "Too many attempts. Try again in \(minutes) min.")
            }
            return String(localized: "Too many requests. Try again in a moment.")
        case .maintenance:
            return String(localized: "Cardsite is down for maintenance. Try again shortly.")
        case .offline:
            return String(localized: "You're offline. Check your connection and try again.")
        case .server(let status, let title):
            return title ?? String(localized: "Something went wrong on our side (\(status)). Try again.")
        case .transport(let message):
            return message
        case .decoding:
            return String(localized: "Cardsite sent something this version of the app can't read. Update the app, or try again.")
        }
    }

    /// Who saved last, for a 409 that names them (a stale block `PUT`).
    public var lastEditorName: String? {
        guard case .conflict(_, _, let lastEditor) = self else { return nil }
        return lastEditor
    }

    /// Worth an inline "Try again" button.
    public var isRetryable: Bool {
        switch self {
        case .offline, .transport, .server, .maintenance, .rateLimited: return true
        default: return false
        }
    }
}

extension APIError {
    /// Classifies a non-2xx response.
    ///
    /// - Parameter credentialCheck: true for requests whose 401 means "wrong
    ///   password" rather than "session gone" (sign-in, account deletion).
    static func from(status: Int, body: Data, headers: [AnyHashable: Any], credentialCheck: Bool) -> APIError {
        let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: body)
        let error = envelope?.error
        let title = error?.title
        switch status {
        case 401:
            // The middleware's own 401 ("Unauthorized") means the token is
            // gone even on a password-checking route.
            if credentialCheck, title != "Unauthorized" {
                return .rejected(title ?? String(localized: "Email or password is incorrect."))
            }
            return .sessionExpired
        case 409:
            let editor = error?.lastEditor?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .conflict(title: title ?? "conflict", message: error?.message,
                             lastEditor: (editor?.isEmpty ?? true) ? nil : editor)
        case 422 where title == "plan_limit_exceeded":
            return .planLimit(limit: error?.limit ?? "", current: error?.current ?? 0, max: error?.max ?? 0)
        case 422 where title == "plan_capability_required":
            return .planCapability(label: error?.label)
        case 400, 403, 404, 422:
            return .invalid(error?.message ?? title ?? String(localized: "That request wasn't accepted."))
        case 429:
            return .rateLimited(retryAfter: retryAfter(headers))
        case 503:
            return .maintenance
        default:
            return .server(status: status, title: title)
        }
    }

    static func retryAfter(_ headers: [AnyHashable: Any]) -> TimeInterval? {
        for (key, value) in headers {
            guard let name = key as? String, name.caseInsensitiveCompare("Retry-After") == .orderedSame else { continue }
            if let seconds = value as? String { return TimeInterval(seconds.trimmingCharacters(in: .whitespaces)) }
            if let seconds = value as? NSNumber { return seconds.doubleValue }
        }
        return nil
    }

    static func from(transportError error: Error) -> APIError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return .offline
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut:
                // The device is online but nothing answers at the API host.
                return .transport(String(localized: "Can't reach Cardsite right now. Try again in a moment."))
            default:
                return .transport(urlError.localizedDescription)
            }
        }
        return .transport(error.localizedDescription)
    }
}
