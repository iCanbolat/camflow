import Foundation

/// Persists the per-org delta-pull cursor (the last `row_version` applied) in
/// `UserDefaults` under `syncCursor.<orgId>`. `0` means a full bootstrap pull.
/// `nonisolated` so the engine can read/write it without main-actor hops.
nonisolated struct SyncCursorStore {
    private let defaults: UserDefaults
    private static let prefix = "syncCursor."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for organizationID: UUID) -> String {
        Self.prefix + organizationID.uuidString
    }

    func cursor(for organizationID: UUID) -> Int {
        defaults.integer(forKey: key(for: organizationID))
    }

    func setCursor(_ value: Int, for organizationID: UUID) {
        defaults.set(value, forKey: key(for: organizationID))
    }

    /// Clears every org's cursor — used on sign-out so the next account
    /// bootstraps from scratch.
    func clearAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
