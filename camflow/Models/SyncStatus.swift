import Foundation

/// Sync lifecycle for every entity. A `Store.touch()` flips a row to `.local`;
/// the sync engine marks rows `.syncing` while a push batch is in flight and
/// `.synced` once the server acks them.
enum SyncStatus: String, Codable {
    case local
    case pending
    /// Transient: the row is in an in-flight push batch. A concurrent local
    /// edit resets it to `.local` (via `touch()`), so a row left `.syncing`
    /// after a failed/interrupted push is re-collected by the next outbox pass.
    case syncing
    case synced
}
