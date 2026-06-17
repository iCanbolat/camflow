import Foundation
import Security

/// Minimal Keychain wrapper for the rotating refresh token. `nonisolated` +
/// `Sendable` so the `TokenStore` actor can call it; Keychain APIs are
/// thread-safe and only an immutable `service` string is stored.
nonisolated struct KeychainStore: Sendable {
    let service: String

    init(service: String = "app.camflow.tokens") {
        self.service = service
    }

    func set(_ value: String, for key: String) {
        var query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    func get(_ key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    func remove(_ key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
