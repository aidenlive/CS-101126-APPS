import Foundation
#if canImport(Security)
import Security
#endif

/// Where the session token lives between launches.
public protocol TokenStore: Sendable {
    func load() -> String?
    func save(_ token: String) throws
    func clear()
}

/// Reads the `exp` claim of a JWT without verifying it, so the app can
/// sign out locally once the 7-day token has expired instead of waiting
/// for a 401. Verification is the server's job.
public enum JWT {
    public static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: exp.doubleValue)
    }

    public static func isExpired(_ token: String, now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        guard let expiry = expiry(of: token) else { return false }
        return expiry.addingTimeInterval(-leeway) <= now
    }
}

/// In-memory store, for previews and tests.
public final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init(token: String? = nil) { self.token = token }

    public func load() -> String? { lock.withLock { token } }
    public func save(_ token: String) throws { lock.withLock { self.token = token } }
    public func clear() { lock.withLock { token = nil } }
}

#if canImport(Security)
/// Keychain store. The token never leaves this device: it is not synced to
/// iCloud Keychain and is not included in device backups.
public struct KeychainTokenStore: TokenStore {
    public enum KeychainError: Error { case status(OSStatus) }

    private let service: String
    private let account = "session-token"

    public init(service: String = "com.cardsite.app.session") {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    public func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ token: String) throws {
        let data = Data(token.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = baseQuery
            insert.merge(attributes) { _, new in new }
            let added = SecItemAdd(insert as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError.status(added) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
#endif
