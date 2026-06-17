import Foundation

// Wire models for the sync engine. These match the backend's `/sync/push` and
// `/sync/pull` contracts (`api/src/sync/sync.dto.ts`, `sync.service.ts`). All
// `nonisolated` + `Sendable` so they cross the networking actors and the
// `@ModelActor` sync context. Dynamic per-entity fields ride inside `SyncRow`
// (payloads and pulled rows); only the envelope is typed here.

// MARK: - Push

/// One local mutation pushed to the server. `idempotencyKey` is replay-safe
/// (`<entity>:<id>:<updatedAtMs>`); `updatedAt` drives Last-Write-Wins.
nonisolated struct SyncMutation: Encodable, Sendable {
    let idempotencyKey: String
    let entity: String
    let op: String // "upsert" | "delete"
    let id: UUID
    let organizationId: UUID
    let updatedAt: Date
    let createdAt: Date?
    /// Entity column values; omitted for deletes.
    let payload: SyncRow?
}

nonisolated struct SyncPushRequest: Encodable, Sendable {
    let deviceId: String?
    let mutations: [SyncMutation]
}

/// Per-item result from `/sync/push`. `applied`: written; `stale`: an
/// equal-or-newer server row won LWW (carried in `server`); `rejected`:
/// refused (e.g. permission), carries a `message`/`code`.
nonisolated struct MutationAck: Decodable, Sendable {
    let id: UUID
    let entity: String
    let op: String
    let status: String // "applied" | "stale" | "rejected"
    let rowVersion: Int?
    let server: SyncRow?
    let message: String?
    let code: String?
}

nonisolated struct SyncPushResponse: Decodable, Sendable {
    let results: [MutationAck]
    let serverTime: Date
}

// MARK: - Pull

/// Delta page from `/sync/pull`: changed/tombstoned rows keyed by entity, the
/// `nextCursor` (max `row_version` seen), and whether more pages remain.
nonisolated struct SyncPullResponse: Decodable, Sendable {
    let changes: [String: [SyncRow]]
    let nextCursor: Int
    let hasMore: Bool
}
