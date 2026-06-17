import Foundation

/// Owns the session tokens: the short-lived **access token lives in memory**,
/// the rotating **refresh token lives in the Keychain**. An `actor` so reads and
/// writes are serialized across the networking layer.
actor TokenStore {
    private var access: String?
    private let keychain: KeychainStore
    private let refreshKey = "refreshToken"

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    var accessToken: String? { access }
    var refreshToken: String? { keychain.get(refreshKey) }

    /// True if a refresh token is on file (a session can be restored on launch).
    var hasSession: Bool { keychain.get(refreshKey) != nil }

    func setTokens(access: String, refresh: String) {
        self.access = access
        keychain.set(refresh, for: refreshKey)
    }

    /// Updates only the in-memory access token (after a refresh that reuses the
    /// same family — the refresh token is rotated separately via `setTokens`).
    func updateAccess(_ token: String) {
        access = token
    }

    func clear() {
        access = nil
        keychain.remove(refreshKey)
    }
}
