import Foundation

/// Sync lifecycle for every entity. v1 is local-only; a future sync engine
/// flips records to `.pending` on change and `.synced` after upload.
enum SyncStatus: String, Codable {
    case local
    case pending
    case synced
}
