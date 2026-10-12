import Foundation
import Observation
import CardsiteKit

/// Session state for the whole app. Owns the API client and the token store;
/// feature models get the client from here.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case launching
        case signedOut
        case signedIn(User)
    }

    private(set) var phase: Phase = .launching
    /// Shown once on the sign-in screen after an involuntary sign-out.
    var signOutNotice: String?
    /// Sheets opened from menu commands on Mac and keyboard shortcuts on iPad.
    var composer: Composer?
    /// The token couldn't be stored, so the next launch starts signed out.
    private(set) var sessionIsEphemeral = false

    enum Composer: String, Identifiable {
        case link, qrCode
        var id: String { rawValue }
    }

    let client: APIClient
    let addresses: AddressBook
    let configuration: AppConfiguration
    private let tokens: TokenStore

    init(configuration: AppConfiguration = .current, tokens: TokenStore? = nil) {
        self.configuration = configuration
        #if canImport(Security)
        self.tokens = tokens ?? KeychainTokenStore()
        #else
        self.tokens = tokens ?? MemoryTokenStore()
        #endif
        self.addresses = AddressBook(publicHost: configuration.publicHost)
        self.client = APIClient(baseURL: configuration.apiBaseURL, userAgent: configuration.userAgent)
    }

    var user: User? {
        if case .signedIn(let user) = phase { return user }
        return nil
    }

    // MARK: Lifecycle

    /// Restores a saved session. A stored token that has expired, or that the
    /// server rejects, is discarded. Offline launches keep the session so the
    /// app opens to its (empty, retryable) screens rather than to sign-in.
    func restore() async {
        guard let token = tokens.load(), !JWT.isExpired(token) else {
            tokens.clear()
            phase = .signedOut
            return
        }
        await client.setToken(token)
        do {
            phase = .signedIn(try await client.currentUser())
        } catch APIError.sessionExpired {
            await endSession(notice: nil)
        } catch {
            // Keep the token; screens will show their own retry state.
            phase = .signedIn(User(id: 0, email: "", name: ""))
        }
    }

    /// True after an offline launch, until the profile has been fetched.
    var needsProfile: Bool { user?.id == 0 }

    func refreshUser() async {
        guard user != nil else { return }
        do {
            phase = .signedIn(try await client.currentUser())
        } catch {
            handle(error)
        }
    }

    // MARK: Auth

    func signIn(email: String, password: String, twoFactorCode: String? = nil, recoveryCode: String? = nil) async throws -> SignInOutcome {
        let outcome = try await client.signIn(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            twoFactorCode: twoFactorCode,
            recoveryCode: recoveryCode
        )
        if case .signedIn(let session) = outcome {
            try await begin(session)
        }
        return outcome
    }

    func register(name: String, email: String, password: String) async throws {
        let session = try await client.register(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        try await begin(session)
    }

    private func begin(_ session: Session) async throws {
        // A keychain failure must not block sign-in: the session still works
        // for this launch, it just won't be remembered.
        do {
            try tokens.save(session.token)
        } catch {
            sessionIsEphemeral = true
        }
        await client.setToken(session.token)
        await client.setWorkspace(nil)
        signOutNotice = nil
        phase = .signedIn(session.user)
    }

    func signOut() async {
        await endSession(notice: nil)
    }

    func deleteAccount(password: String) async throws {
        try await client.deleteAccount(password: password)
        await endSession(notice: String(localized: "Your account and everything in it has been deleted."))
    }

    func updateName(_ name: String) async throws {
        let updated = try await client.updateName(name.trimmingCharacters(in: .whitespacesAndNewlines))
        phase = .signedIn(updated)
    }

    private func endSession(notice: String?) async {
        tokens.clear()
        await client.setToken(nil)
        await client.setWorkspace(nil)
        composer = nil
        signOutNotice = notice
        phase = .signedOut
    }

    /// Central place every feature model reports errors to: an expired session
    /// signs the user out wherever it is noticed.
    func handle(_ error: Error) {
        if let apiError = error as? APIError, apiError == .sessionExpired, user != nil {
            Task { await endSession(notice: APIError.sessionExpired.localizedDescription) }
        }
    }
}

/// Values set per build configuration in Config/*.xcconfig and read from Info.plist.
struct AppConfiguration: Sendable {
    let apiBaseURL: URL
    let publicHost: String
    let webURL: URL
    let userAgent: String

    static let current: AppConfiguration = {
        let info = Bundle.main.infoDictionary ?? [:]
        let api = (info["CSAPIBaseURL"] as? String).flatMap(URL.init(string:)) ?? URL(string: "https://cardsite.com")!
        let web = (info["CSWebURL"] as? String).flatMap(URL.init(string:)) ?? URL(string: "https://cardsite.com")!
        let host = (info["CSPublicHost"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "card.site"
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        #if os(macOS)
        let platform = "macOS"
        #else
        let platform = "iOS"
        #endif
        return AppConfiguration(apiBaseURL: api, publicHost: host, webURL: web,
                                userAgent: "Cardsite-Apple/\(version) (\(build); \(platform))")
    }()

    // Web routes from marketing/src/pages (/legal/[slug], /contact).
    // Deliberately no link to /plans: the app sells nothing and must not
    // point to purchasing elsewhere (App Review 3.1.1; see
    // docs/launch/native-apple.md → Purchasing).
    var privacyURL: URL { webURL.appendingPathComponent("legal/privacy") }
    var termsURL: URL { webURL.appendingPathComponent("legal/terms") }
    var supportURL: URL { webURL.appendingPathComponent("contact") }

    static let preview = AppConfiguration(
        apiBaseURL: URL(string: "http://localhost:8080")!,
        publicHost: "card.site",
        webURL: URL(string: "https://cardsite.com")!,
        userAgent: "Cardsite-Apple/preview"
    )
}
