import Foundation
import Observation
import CardsiteKit

/// Security and profile settings: timezone, password, two-factor
/// authentication and API tokens.
///
/// Two-factor state comes from `GET /auth/2fa/recovery-codes`, not from
/// `app.user`: `GET /user` is cached on the server for about 10 minutes, so
/// the profile would still say "off" right after enabling it.
@MainActor
@Observable
final class AccountSettingsModel {
    private(set) var twoFactor: Loadable<TwoFactorStatus> = .idle
    private(set) var tokens: Loadable<APITokenList> = .idle
    private(set) var tokensRefreshError: APIError?
    /// The timezone saved from this screen. `app.user` keeps the value it was
    /// signed in with until the server's profile cache expires.
    private(set) var savedTimezone: String?

    let client: APIClient
    @ObservationIgnored var onError: @MainActor (any Error) -> Void

    init(client: APIClient, onError: @escaping @MainActor (any Error) -> Void = { _ in }) {
        self.client = client
        self.onError = onError
    }

    // MARK: Profile

    /// Saves the timezone and returns the updated user, which the caller
    /// hands to `AppModel.replaceUser(_:)`.
    @discardableResult
    func saveTimezone(_ identifier: String) async throws -> User {
        do {
            let user = try await client.updateTimezone(identifier)
            savedTimezone = user.timezone ?? identifier
            return user
        } catch {
            onError(error)
            throw error
        }
    }

    /// 8–64 bytes, the rule register, reset and sign-in share. Sign-in reads
    /// at most 64 bytes, so a longer password could never be used.
    static func passwordProblem(new: String, confirm: String) -> String? {
        if new != confirm { return String(localized: "Passwords do not match") }
        let length = new.utf8.count
        if length < 8 || length > 64 { return String(localized: "Use 8 to 64 characters.") }
        return nil
    }

    func changePassword(current: String, new: String) async throws {
        do {
            try await client.changePassword(current: current, new: new)
        } catch {
            onError(error)
            throw error
        }
    }

    // MARK: Two-factor authentication

    func loadTwoFactor(force: Bool = false) async {
        if !force, twoFactor.value != nil { return }
        if twoFactor.value == nil { twoFactor = .loading }
        do {
            twoFactor = .loaded(try await client.twoFactorStatus())
        } catch is CancellationError {
            if case .loading = twoFactor { twoFactor = .idle }
        } catch {
            onError(error)
            if twoFactor.value == nil { twoFactor = .failed(error.asAPIError) }
        }
    }

    func startTwoFactorSetup() async throws -> TwoFactorSetup {
        do {
            return try await client.startTwoFactorSetup()
        } catch {
            onError(error)
            throw error
        }
    }

    /// Returns the recovery codes, which are shown this once.
    func verifyTwoFactor(code: String) async throws -> [String] {
        do {
            let codes = try await client.verifyTwoFactor(code: code)
            twoFactor = .loaded(TwoFactorStatus(isEnabled: true, remainingRecoveryCodes: codes.count))
            return codes
        } catch {
            onError(error)
            throw error
        }
    }

    func disableTwoFactor(password: String) async throws {
        do {
            try await client.disableTwoFactor(password: password)
            twoFactor = .loaded(TwoFactorStatus(isEnabled: false, remainingRecoveryCodes: 0))
        } catch {
            onError(error)
            throw error
        }
    }

    func regenerateRecoveryCodes(password: String) async throws -> [String] {
        do {
            let codes = try await client.regenerateRecoveryCodes(password: password)
            twoFactor = .loaded(TwoFactorStatus(isEnabled: true, remainingRecoveryCodes: codes.count))
            return codes
        } catch {
            onError(error)
            throw error
        }
    }

    // MARK: API tokens

    /// Tokens as a list state, for ``ListStateView``. Active tokens first.
    var tokenListState: Loadable<[APIToken]> {
        switch tokens {
        case .idle: return .idle
        case .loading: return .loading
        case .failed(let error): return .failed(error)
        case .loaded(let list):
            let now = Date()
            return .loaded(list.tokens.sorted { lhs, rhs in
                let l = lhs.status(at: now) == .active, r = rhs.status(at: now) == .active
                if l != r { return l }
                return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
            })
        }
    }

    var availableScopes: [String] { tokens.value?.scopes ?? [] }

    func loadTokens(force: Bool = false) async {
        if !force, tokens.value != nil { return }
        if tokens.value == nil { tokens = .loading }
        do {
            tokens = .loaded(try await client.apiTokens())
            tokensRefreshError = nil
        } catch is CancellationError {
            if case .loading = tokens { tokens = .idle }
        } catch {
            onError(error)
            if tokens.value == nil {
                tokens = .failed(error.asAPIError)
            } else {
                tokensRefreshError = error.asAPIError
            }
        }
    }

    func dismissTokensRefreshError() { tokensRefreshError = nil }

    func createToken(name: String, scopes: [String], expiresAt: Date?) async throws -> CreatedAPIToken {
        do {
            let created = try await client.createAPIToken(name: name, scopes: scopes, expiresAt: expiresAt)
            if let list = tokens.value {
                tokens = .loaded(APITokenList(scopes: list.scopes, tokens: [created.token] + list.tokens))
            }
            return created
        } catch {
            onError(error)
            throw error
        }
    }

    func revokeToken(_ token: APIToken) async throws {
        do {
            try await client.revokeAPIToken(id: token.id)
            if let list = tokens.value {
                let revoked = APIToken(id: token.id, name: token.name, scopes: token.scopes,
                                       lastUsedAt: token.lastUsedAt, expiresAt: token.expiresAt,
                                       revokedAt: Date(), createdAt: token.createdAt)
                tokens = .loaded(APITokenList(scopes: list.scopes,
                                              tokens: list.tokens.map { $0.id == token.id ? revoked : $0 }))
            }
        } catch {
            onError(error)
            throw error
        }
    }

    /// Sample data for previews; skips the first fetches.
    func seed(twoFactor: TwoFactorStatus, tokens: APITokenList) {
        self.twoFactor = .loaded(twoFactor)
        self.tokens = .loaded(tokens)
    }
}
