import Foundation
#if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
import WatchConnectivity
#endif

/*
 The signed-in session, shared with the app's extensions and its watch app.

 The app owns the session. Its extensions (widgets, App Intents run from
 the widgets, the share extension) read it from two places:

 · the JWT, from the Keychain access group
   `$(AppIdentifierPrefix)$(CARDSITE_BUNDLE_ID).shared`;
 · the API base URL, the public host and the selected workspace, from the
   App Group `group.$(CARDSITE_BUNDLE_ID)` user defaults.

 Both identifiers come from build settings (`CARDSITE_APP_GROUP` and
 `CARDSITE_KEYCHAIN_GROUP` in project.yml) through the `CSAppGroup` and
 `CSKeychainGroup` Info.plist keys of each bundle, so nothing here names a
 team or a bundle ID.

 The watch has no shared keychain with the phone. The iPhone app sends it
 the same snapshot over WatchConnectivity (`WatchSessionRelay`), and the
 watch keeps the token in its own keychain.
 */

/// What an extension needs besides the token to call the API as the user.
public struct SessionContext: Codable, Sendable, Hashable {
    public let baseURL: URL
    /// `card.site`: the host short links are served from.
    public let publicHost: String
    /// The workspace selected in the app, sent as `X-Workspace-ID`. Nil is
    /// the personal workspace.
    public let workspaceID: Int?

    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case publicHost = "public_host"
        case workspaceID = "workspace_id"
    }

    public init(baseURL: URL, publicHost: String, workspaceID: Int?) {
        self.baseURL = baseURL
        self.publicHost = publicHost
        self.workspaceID = workspaceID
    }

    public var addresses: AddressBook { AddressBook(publicHost: publicHost) }
}

/// A usable session: a token that hasn't expired, and where to send it.
public struct SessionSnapshot: Sendable, Hashable {
    public let token: String
    public let context: SessionContext

    public init(token: String, context: SessionContext) {
        self.token = token
        self.context = context
    }

    /// An API client signed in as the user, scoped to their workspace.
    public func makeClient(userAgent: String) async -> APIClient {
        let client = APIClient(baseURL: context.baseURL, token: token, userAgent: userAgent)
        await client.setWorkspace(context.workspaceID)
        return client
    }
}

/// The App Group and Keychain group shared by the app and its extensions.
public struct SharedSession: Sendable, Hashable {
    /// e.g. `group.com.cardsite.app`.
    public let appGroup: String
    /// e.g. `ABCDE12345.com.cardsite.app.shared`.
    public let keychainGroup: String

    /// The Keychain service the session token is stored under, the same as
    /// ``KeychainTokenStore``'s default.
    public static let tokenService = "com.cardsite.app.session"

    private enum Key {
        static let baseURL = "cardsite.shared.apiBaseURL"
        static let publicHost = "cardsite.shared.publicHost"
        static let workspaceID = "cardsite.shared.workspaceID"
    }

    public init(appGroup: String, keychainGroup: String) {
        self.appGroup = appGroup
        self.keychainGroup = keychainGroup
    }

    /// The groups named by `CSAppGroup` and `CSKeychainGroup` in `bundle`'s
    /// Info.plist. Nil when either is missing or wasn't expanded: an
    /// unsigned build (CI's `CODE_SIGNING_ALLOWED=NO`) leaves
    /// `$(AppIdentifierPrefix)` empty, so the keychain group starts with
    /// a dot, and sharing is off rather than pointed at a group the app
    /// isn't entitled to.
    public static func fromBundle(_ bundle: Bundle = .main) -> SharedSession? {
        guard let group = bundle.object(forInfoDictionaryKey: "CSAppGroup") as? String,
              let keychain = bundle.object(forInfoDictionaryKey: "CSKeychainGroup") as? String,
              isExpanded(group), isExpanded(keychain) else { return nil }
        return SharedSession(appGroup: group, keychainGroup: keychain)
    }

    /// The main bundle's groups (see ``fromBundle(_:)``).
    public static var current: SharedSession? { fromBundle(.main) }

    private static func isExpanded(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix(".") && !value.contains("$(")
    }

    // MARK: Storage

    /// The App Group's user defaults. Created on each access: `UserDefaults`
    /// is thread-safe but not `Sendable`, so it isn't stored here.
    public var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// The App Group container, for files the app and its extensions share
    /// (the widgets' cached QR images).
    public var containerURL: URL? {
        #if canImport(Darwin)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        #else
        nil
        #endif
    }

    #if canImport(Security)
    /// The token store in the shared Keychain group. The app uses this in
    /// place of the default ``KeychainTokenStore`` so its extensions can
    /// read what it saves.
    public var tokenStore: KeychainTokenStore {
        KeychainTokenStore(service: Self.tokenService, accessGroup: keychainGroup)
    }

    /// Moves a token saved before the shared group existed (in the app's
    /// own access group) into the shared group, once. Call it before the
    /// first ``tokenStore`` read at launch.
    ///
    /// A query without an access group matches every group the app is
    /// entitled to, so the old item can't be deleted on its own. The token
    /// is first saved to the shared group, which proves the entitlement
    /// (if that fails nothing changes and the app keeps working from the
    /// old item); then every copy is deleted and the shared one saved
    /// again. Leaving the old item behind would bring a session back after
    /// the user signs out.
    public func adoptLegacyToken() {
        let shared = tokenStore
        guard shared.load() == nil else { return }
        let legacy = KeychainTokenStore(service: Self.tokenService)
        guard let token = legacy.load() else { return }
        do {
            try shared.save(token)
        } catch {
            return
        }
        legacy.clear()
        try? shared.save(token)
    }
    #endif

    // MARK: App side

    /// Mirrors the session's context for the extensions. The token itself
    /// is already in the shared Keychain group (``tokenStore``).
    public func publish(_ context: SessionContext) {
        guard let defaults else { return }
        defaults.set(context.baseURL.absoluteString, forKey: Key.baseURL)
        defaults.set(context.publicHost, forKey: Key.publicHost)
        if let id = context.workspaceID {
            defaults.set(id, forKey: Key.workspaceID)
        } else {
            defaults.removeObject(forKey: Key.workspaceID)
        }
    }

    /// Forgets the mirrored context on sign-out. The app clears the token
    /// through its token store.
    public func clear() {
        guard let defaults else { return }
        defaults.removeObject(forKey: Key.baseURL)
        defaults.removeObject(forKey: Key.publicHost)
        defaults.removeObject(forKey: Key.workspaceID)
    }

    // MARK: Extension side

    /// The mirrored context, or nil when the app has never published one
    /// or has signed out.
    public func context() -> SessionContext? {
        guard let defaults,
              let base = defaults.string(forKey: Key.baseURL).flatMap(URL.init(string:)) else { return nil }
        let host = defaults.string(forKey: Key.publicHost).flatMap { $0.isEmpty ? nil : $0 } ?? "card.site"
        return SessionContext(baseURL: base, publicHost: host,
                              workspaceID: defaults.object(forKey: Key.workspaceID) as? Int)
    }

    #if canImport(Security)
    /// The signed-in session, or nil when signed out or when the 7-day
    /// token has expired (there is no refresh token: the user signs in
    /// again in the app).
    public func snapshot() -> SessionSnapshot? {
        guard let context = context(),
              let token = tokenStore.load(), !JWT.isExpired(token) else { return nil }
        return SessionSnapshot(token: token, context: context)
    }
    #endif
}

// MARK: - Deep links

/// `cardsite://` URLs the widgets and the share extension open the app with.
/// The app registers the scheme (`CFBundleURLTypes` in Info.plist) and
/// routes these in `.onOpenURL`.
public enum CardsiteDeepLink: Hashable, Sendable {
    case home
    case link(id: Int)
    case qrCode(id: Int)
    /// A new short link to `destination`, as the share extension offers
    /// when the user isn't signed in yet.
    case createLink(destination: URL)

    public static let scheme = "cardsite"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .home:
            components.host = "home"
        case .link(let id):
            components.host = "links"
            components.path = "/\(id)"
        case .qrCode(let id):
            components.host = "qr-codes"
            components.path = "/\(id)"
        case .createLink(let destination):
            components.host = "new-link"
            components.queryItems = [URLQueryItem(name: "url", value: destination.absoluteString)]
        }
        return components.url ?? URL(fileURLWithPath: "/")
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let id = Int(components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        switch components.host?.lowercased() {
        case "home":
            self = .home
        case "links":
            guard let id else { return nil }
            self = .link(id: id)
        case "qr-codes":
            guard let id else { return nil }
            self = .qrCode(id: id)
        case "new-link":
            guard let raw = components.queryItems?.first(where: { $0.name == "url" })?.value,
                  let destination = Destination.normalized(raw) else { return nil }
            self = .createLink(destination: destination)
        default:
            return nil
        }
    }
}

// MARK: - Watch relay

#if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
/// Carries the session from the iPhone app to the watch app over
/// WatchConnectivity's application context: the latest state wins, it is
/// delivered when the watch app next runs, and the transport between the
/// paired devices is encrypted.
///
/// iPhone: `WatchSessionRelay.shared.activate()` at launch, then
/// `send(_:)` on sign-in, workspace switch and sign-out.
/// Watch: `activate { message in … }`; the last context received is
/// delivered again on every activation.
public final class WatchSessionRelay: NSObject, WCSessionDelegate, @unchecked Sendable {
    /// What the iPhone says about the session.
    public enum Message: Sendable, Hashable {
        case signedIn(SessionSnapshot)
        case signedOut
    }

    public static let shared = WatchSessionRelay()

    private let lock = NSLock()
    /// Guarded by `lock`.
    private var pending: [String: Any]?
    private var receiver: (@Sendable (Message) -> Void)?

    override private init() {
        super.init()
    }

    /// Starts the session. `onReceive` runs on a background queue for each
    /// message from the other device (the watch side passes one).
    public func activate(onReceive: (@Sendable (Message) -> Void)? = nil) {
        guard WCSession.isSupported() else { return }
        lock.withLock { receiver = onReceive }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// iPhone: the session for the watch, or nil to sign it out. Held and
    /// sent once the session is active and the watch app is installed.
    public func send(_ snapshot: SessionSnapshot?) {
        let payload = Self.encode(snapshot.map(Message.signedIn) ?? .signedOut)
        lock.withLock { pending = payload }
        flush()
    }

    private func flush() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        guard let payload = lock.withLock({ pending }) else { return }
        do {
            try session.updateApplicationContext(payload)
            lock.withLock { pending = nil }
        } catch {
            // Kept pending; retried on the next activation or watch state change.
        }
    }

    private func deliver(_ context: [String: Any]) {
        guard let message = Self.decode(context),
              let receiver = lock.withLock({ receiver }) else { return }
        receiver(message)
    }

    // MARK: Payload

    static func encode(_ message: Message) -> [String: Any] {
        // `sent_at` makes every update distinct, so a repeat sign-in is
        // still delivered.
        var payload: [String: Any] = ["v": 1, "sent_at": Date().timeIntervalSince1970]
        switch message {
        case .signedOut:
            payload["signed_out"] = true
        case .signedIn(let snapshot):
            payload["token"] = snapshot.token
            payload["base_url"] = snapshot.context.baseURL.absoluteString
            payload["public_host"] = snapshot.context.publicHost
            if let id = snapshot.context.workspaceID { payload["workspace_id"] = id }
        }
        return payload
    }

    static func decode(_ payload: [String: Any]) -> Message? {
        guard payload["v"] as? Int == 1 else { return nil }
        if payload["signed_out"] as? Bool == true { return .signedOut }
        guard let token = payload["token"] as? String,
              let base = (payload["base_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let host = payload["public_host"] as? String ?? "card.site"
        let context = SessionContext(baseURL: base, publicHost: host, workspaceID: payload["workspace_id"] as? Int)
        return .signedIn(SessionSnapshot(token: token, context: context))
    }

    // MARK: WCSessionDelegate

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                        error: Error?) {
        guard activationState == .activated else { return }
        #if os(watchOS)
        let context = session.receivedApplicationContext
        if !context.isEmpty { deliver(context) }
        #else
        flush()
        #endif
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(applicationContext)
    }

    #if os(iOS)
    public func sessionWatchStateDidChange(_ session: WCSession) {
        flush()
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        // The user switched watches: activate again for the new one.
        WCSession.default.activate()
    }
    #endif
}
#endif
