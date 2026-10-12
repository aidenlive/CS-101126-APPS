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
    /// Sheets opened from menu commands on Mac, keyboard shortcuts on iPad
    /// and Home's quick create.
    var composer: Composer?
    /// The token couldn't be stored, so the next launch starts signed out.
    private(set) var sessionIsEphemeral = false

    /// A create sheet, optionally prefilled.
    ///
    /// `.link`, `.qrCode`, `.bioPage` and the six resource kinds open an
    /// empty editor. Home's paste
    /// box opens `.link(destination:)`, and a link's page opens
    /// `composeQRCode(for:)`; `MainView.composerSheet` hands `prefill` to
    /// `LinkEditorView(prefill:)` and `QRCodeEditorView(prefillURL:)`.
    struct Composer: Identifiable, Hashable {
        enum Kind: String, Hashable, Sendable {
            case link, qrCode, bioPage
            case vcard, event, paymentLink, file, staticPage, splash

            /// The resource editor this kind opens, for the six resource types.
            var resourceKind: ResourceKind? {
                switch self {
                case .link, .qrCode, .bioPage: return nil
                case .vcard: return .vcard
                case .event: return .event
                case .paymentLink: return .paymentLink
                case .file: return .file
                case .staticPage: return .staticPage
                case .splash: return .splash
                }
            }
        }

        let kind: Kind
        /// The URL the editor starts with: a short link's destination, or
        /// the address a QR code encodes.
        var prefill: URL?

        var id: String { kind.rawValue }

        static let link = Composer(kind: .link)
        static let qrCode = Composer(kind: .qrCode)
        static let bioPage = Composer(kind: .bioPage)

        /// A new short link to what the user pasted. Text that isn't a web
        /// address yet ("example.com/menu") is normalised the way the
        /// editor will; text that can't be one opens the editor empty.
        static func link(destination: String) -> Composer {
            let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .link }
            return Composer(kind: .link, prefill: Destination.normalized(trimmed) ?? URL(string: trimmed))
        }
    }

    let client: APIClient
    let addresses: AddressBook
    let configuration: AppConfiguration
    private let tokens: TokenStore
    private let defaults: UserDefaults

    // MARK: Workspace scope

    /// The workspaces the user belongs to, for the switcher.
    private(set) var workspaces: Loadable<[Workspace]> = .idle
    /// The selected workspace, sent as `X-Workspace-ID`. Nil is the server's
    /// default, the personal workspace.
    private(set) var workspaceID: Int?
    /// Changes on every switch. `RootView` keys the signed-in shell on it,
    /// so every list model and screen is rebuilt for the new scope rather
    /// than showing one workspace's rows under another's name.
    private(set) var workspaceScope = 0
    private static let workspaceKey = "cardsite.workspaceID"

    init(configuration: AppConfiguration = .current, tokens: TokenStore? = nil, defaults: UserDefaults = .standard) {
        self.configuration = configuration
        self.addresses = AddressBook(publicHost: configuration.publicHost)
        #if DEBUG
        // UI tests and screenshots: the in-app fixture server, a token held
        // in memory and a throwaway defaults domain (Cardsite/Debug).
        if FixtureMode.isEnabled {
            let suite = "cardsite.fixtures"
            let fixtureDefaults = UserDefaults(suiteName: suite) ?? defaults
            fixtureDefaults.removePersistentDomain(forName: suite)
            self.defaults = fixtureDefaults
            self.tokens = FixtureMode.tokenStore()
            self.client = APIClient(baseURL: configuration.apiBaseURL, transport: FixtureTransport(),
                                    userAgent: configuration.userAgent)
            return
        }
        #endif
        #if canImport(Security)
        self.tokens = tokens ?? KeychainTokenStore()
        #else
        self.tokens = tokens ?? MemoryTokenStore()
        #endif
        self.defaults = defaults
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
        // The workspace chosen last time. Validated against the list once
        // it loads; a workspace the user has left falls back to personal.
        workspaceID = defaults.object(forKey: Self.workspaceKey) as? Int
        await client.setWorkspace(workspaceID)
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
        await resetWorkspace()
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

    /// A newer copy of the signed-in user, such as the one `PUT /account`
    /// returns after a timezone change. `GET /user` stays cached on the
    /// server for about 10 minutes, so this is how the app keeps up.
    func replaceUser(_ user: User) {
        guard self.user != nil else { return }
        phase = .signedIn(user)
    }

    // MARK: Composer

    /// Opens a create sheet, optionally prefilled with a URL.
    func compose(_ kind: Composer.Kind, prefill: URL? = nil) {
        composer = Composer(kind: kind, prefill: prefill)
    }

    /// A new QR code that encodes `url`, such as a short link's address.
    func composeQRCode(for url: URL) {
        compose(.qrCode, prefill: url)
    }

    private func endSession(notice: String?) async {
        tokens.clear()
        await client.setToken(nil)
        await resetWorkspace()
        composer = nil
        signOutNotice = notice
        phase = .signedOut
    }

    // MARK: Workspaces

    /// The workspace on screen: the selected one, else the personal one.
    var currentWorkspace: Workspace? {
        guard let list = workspaces.value else { return nil }
        return list.first { $0.id == workspaceID } ?? list.first { $0.isPersonal } ?? list.first
    }

    /// Loads the switcher's list. A remembered workspace the user is no
    /// longer in (left, removed, deleted) falls back to personal.
    func loadWorkspaces() async {
        if workspaces.value == nil { workspaces = .loading }
        do {
            let list = try await client.workspaces()
            workspaces = .loaded(list)
            if let id = workspaceID, !list.contains(where: { $0.id == id }) {
                await apply(workspace: nil)
            }
        } catch is CancellationError {
            if case .loading = workspaces { workspaces = .idle }
        } catch {
            handle(error)
            if workspaces.value == nil { workspaces = .failed(error.asAPIError) }
        }
    }

    /// Switches every request to `id` (nil: personal) and rebuilds the
    /// signed-in shell so each screen reloads in the new scope. Remembered
    /// across launches until sign-out. Also what the Workspace screen's
    /// `\.switchWorkspace` action calls after creating, leaving or
    /// deleting a workspace.
    func selectWorkspace(_ id: Int?) async {
        guard id != workspaceID else { return }
        await apply(workspace: id)
        // A just-created workspace isn't in the list yet.
        if let id, workspaces.value?.contains(where: { $0.id == id }) != true {
            await loadWorkspaces()
        }
    }

    private func apply(workspace id: Int?) async {
        workspaceID = id
        if let id {
            defaults.set(id, forKey: Self.workspaceKey)
        } else {
            defaults.removeObject(forKey: Self.workspaceKey)
        }
        await client.setWorkspace(id)
        composer = nil
        workspaceScope += 1
    }

    private func resetWorkspace() async {
        workspaceID = nil
        workspaces = .idle
        defaults.removeObject(forKey: Self.workspaceKey)
        await client.setWorkspace(nil)
    }

    /// Central place every feature model reports errors to: an expired session
    /// signs the user out wherever it is noticed.
    func handle(_ error: Error) {
        if let apiError = error as? APIError, apiError == .sessionExpired, user != nil {
            Task { await endSession(notice: APIError.sessionExpired.localizedDescription) }
        }
    }

    #if DEBUG
    /// For previews: signed in, with workspaces, against a host that isn't
    /// running, so screens show the data their previews hand them.
    static func preview(
        user: User = User(id: 4, email: "ada@example.com", name: "Ada Lovelace"),
        workspaces: [Workspace] = [
            Workspace(id: 234, name: "Personal", isPersonal: true),
            Workspace(id: 301, name: "Acme Marketing", isPersonal: false, role: "admin"),
        ]
    ) -> AppModel {
        let model = AppModel(configuration: .preview, tokens: MemoryTokenStore(),
                             defaults: UserDefaults(suiteName: "cardsite.preview") ?? .standard)
        model.phase = .signedIn(user)
        model.workspaces = .loaded(workspaces)
        model.workspaceID = workspaces.first?.id
        return model
    }
    #endif
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
