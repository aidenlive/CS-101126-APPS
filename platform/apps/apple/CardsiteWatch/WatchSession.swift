import Foundation
import Observation
import CardsiteKit

/// The watch's copy of the iPhone session. The iPhone app sends it over
/// WatchConnectivity (`WatchSessionRelay`) on sign-in, workspace switch and
/// sign-out; the watch keeps the token in its own keychain and the rest in
/// its defaults, so it opens signed in without the phone nearby.
@MainActor
@Observable
final class WatchSession {
    private(set) var snapshot: SessionSnapshot?
    /// Changes whenever the session does; the root view keys its screens on
    /// it so nothing from the previous session or workspace stays on screen.
    private(set) var scope = 0

    private var client: APIClient?
    private let tokens: TokenStore
    private let defaults: UserDefaults
    private static let contextKey = "cardsite.watch.context"

    init(tokens: TokenStore? = nil, defaults: UserDefaults = .standard) {
        #if canImport(Security)
        let store = tokens ?? KeychainTokenStore(service: "com.cardsite.app.watch.session")
        #else
        let store = tokens ?? MemoryTokenStore()
        #endif
        self.tokens = store
        self.defaults = defaults
        if let token = store.load(), !JWT.isExpired(token),
           let data = defaults.data(forKey: Self.contextKey),
           let context = try? JSONDecoder().decode(SessionContext.self, from: data) {
            snapshot = SessionSnapshot(token: token, context: context)
        }
    }

    var isSignedIn: Bool { snapshot != nil }
    var addresses: AddressBook { snapshot?.context.addresses ?? AddressBook() }

    /// Starts listening to the iPhone. Each message replaces the session.
    func activate() {
        WatchSessionRelay.shared.activate { [weak self] message in
            Task { @MainActor in self?.apply(message) }
        }
    }

    func apply(_ message: WatchSessionRelay.Message) {
        switch message {
        case .signedIn(let next):
            guard next != snapshot else { return }
            try? tokens.save(next.token)
            if let data = try? JSONEncoder().encode(next.context) {
                defaults.set(data, forKey: Self.contextKey)
            }
            snapshot = next
        case .signedOut:
            guard snapshot != nil else { return }
            signOut()
            return
        }
        client = nil
        scope += 1
    }

    /// A client for the current session; nil when signed out.
    func apiClient() async -> APIClient? {
        if let client { return client }
        guard let snapshot else { return nil }
        let made = await snapshot.makeClient(userAgent: Self.userAgent)
        // The session may have changed while the workspace was being set.
        guard snapshot == self.snapshot else { return nil }
        client = made
        return made
    }

    /// Every screen reports failures here: an expired or revoked token
    /// signs the watch out until the iPhone sends a new one.
    func handle(_ error: Error) {
        if let error = error as? APIError, error == .sessionExpired {
            signOut()
        }
    }

    private func signOut() {
        tokens.clear()
        defaults.removeObject(forKey: Self.contextKey)
        snapshot = nil
        client = nil
        scope += 1
    }

    private static var userAgent: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return "Cardsite-Apple/\(version) (\(build); watchOS)"
    }

    #if DEBUG
    static func preview(signedIn: Bool = true) -> WatchSession {
        let session = WatchSession(tokens: MemoryTokenStore(),
                                   defaults: UserDefaults(suiteName: "cardsite.watch.preview") ?? .standard)
        if signedIn {
            let context = SessionContext(baseURL: URL(string: "http://localhost:8080")!, publicHost: "card.site", workspaceID: nil)
            session.snapshot = SessionSnapshot(token: "preview", context: context)
        }
        return session
    }
    #endif
}
