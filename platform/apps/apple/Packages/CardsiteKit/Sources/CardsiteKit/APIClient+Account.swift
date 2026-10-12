import Foundation

/// Account settings, two-factor authentication, API tokens and preferences.
///
/// Every call that checks a password or code is sent with
/// `credentialCheck: true`: the server answers a wrong one with 401, the
/// same status as an expired session, and without the flag the app would
/// sign the user out (ContractTests/README.md, quirk 12).
public extension APIClient {

    // MARK: Profile

    /// `PUT /account {timezone}` with an IANA identifier. Returns the updated
    /// user; keep it, because `GET /user` stays cached for about 10 minutes.
    func updateTimezone(_ identifier: String) async throws -> User {
        try await send(.put, "api/v1/account", body: ["timezone": identifier])
    }

    /// `PUT /account/password`. The new password must be 8–64 characters.
    /// A wrong current password throws ``APIError/rejected(_:)``; the session
    /// stays valid either way.
    func changePassword(current: String, new: String) async throws {
        try await sendIgnoringBody(.put, "api/v1/account/password",
                                   body: ["current_password": current, "new_password": new],
                                   credentialCheck: true)
    }

    // MARK: Two-factor authentication

    func twoFactorStatus() async throws -> TwoFactorStatus {
        try await send(.get, "api/v1/auth/2fa/recovery-codes")
    }

    /// Starts enrolment. 409 when 2FA is already on.
    func startTwoFactorSetup() async throws -> TwoFactorSetup {
        try await send(.post, "api/v1/auth/2fa/setup")
    }

    /// Confirms enrolment with a 6-digit code and returns the recovery codes,
    /// which the server never shows again. A wrong code throws
    /// ``APIError/rejected(_:)``.
    func verifyTwoFactor(code: String) async throws -> [String] {
        let payload: RecoveryCodesPayload = try await send(.post, "api/v1/auth/2fa/verify",
                                                           body: ["code": code], credentialCheck: true)
        return payload.recoveryCodes ?? []
    }

    /// Turns 2FA off. A wrong password throws ``APIError/rejected(_:)``.
    func disableTwoFactor(password: String) async throws {
        try await sendIgnoringBody(.delete, "api/v1/auth/2fa", body: ["password": password], credentialCheck: true)
    }

    /// Replaces every recovery code with a fresh set of 10.
    func regenerateRecoveryCodes(password: String) async throws -> [String] {
        let payload: RecoveryCodesPayload = try await send(.post, "api/v1/auth/2fa/recovery-codes",
                                                           body: ["password": password], credentialCheck: true)
        return payload.recoveryCodes ?? []
    }

    // MARK: API tokens

    func apiTokens() async throws -> APITokenList {
        try await send(.get, "api/v1/account/tokens")
    }

    /// Mints a token pinned to the current workspace. Needs at least one
    /// scope; `expiresAt` must be in the future. Refused with
    /// ``APIError/planCapability(label:)`` when the plan has no API access.
    func createAPIToken(name: String, scopes: [String], expiresAt: Date? = nil) async throws -> CreatedAPIToken {
        var body: [String: JSONValue] = [
            "name": .string(name),
            "scopes": .array(scopes.map(JSONValue.string)),
        ]
        if let expiresAt {
            // Go decodes `*time.Time` from RFC 3339 only.
            body["expires_at"] = .string(expiresAt.formatted(Date.ISO8601FormatStyle()))
        }
        return try await send(.post, "api/v1/account/tokens", body: body)
    }

    /// Revokes immediately. The row stays in the list as an audit record.
    func revokeAPIToken(id: Int) async throws {
        try await sendIgnoringBody(.delete, "api/v1/account/tokens/\(id)")
    }

    // MARK: Preferences

    func preferences() async throws -> AccountPreferences {
        let value: AccountPreferences? = try await sendOptional(.get, "api/v1/account/preferences")
        return value ?? AccountPreferences()
    }

    /// Replaces the whole object; pass every key, not only the changed ones.
    func updatePreferences(_ preferences: AccountPreferences) async throws -> AccountPreferences {
        let value: AccountPreferences? = try await sendOptional(.put, "api/v1/account/preferences", body: preferences)
        return value ?? preferences
    }
}
