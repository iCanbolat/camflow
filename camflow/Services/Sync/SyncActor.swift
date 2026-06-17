import Foundation
import SwiftData

/// Owns a background `ModelContext` so sync batches never block the main-actor
/// `@Query` UI. All SwiftData reads/writes for sync happen here; the `SyncEngine`
/// drives the networking on the main actor and hands Sendable values across.
@ModelActor
actor SyncActor {
    /// Collects dirty rows for `organizationID` into push mutations, ordered
    /// parents → children so the backend's FK checks pass. Each collected row is
    /// flipped to `.syncing`; a concurrent `touch()` resets it to `.local`, so an
    /// edit made during the in-flight push is re-collected next cycle. The
    /// idempotency key (`<entity>:<id>:<updatedAtMs>`) is replay-safe.
    func collectOutbox(organizationID orgID: UUID) -> [SyncMutation] {
        var mutations: [SyncMutation] = []

        func collect<T: SyncPushable>(_ type: T.Type) {
            let rows = (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
            for row in rows where row.syncStatus != .synced {
                guard let rowOrg = row.syncOrganizationID(activeOrg: orgID), rowOrg == orgID else { continue }
                let isDelete = row.deletedAt != nil
                let updatedMs = Int(row.updatedAt.timeIntervalSince1970 * 1000)
                mutations.append(SyncMutation(
                    idempotencyKey: "\(T.syncEntity):\(row.id.uuidString):\(updatedMs)",
                    entity: T.syncEntity,
                    op: isDelete ? "delete" : "upsert",
                    id: row.id,
                    organizationId: orgID,
                    updatedAt: row.updatedAt,
                    createdAt: row.createdAt,
                    payload: isDelete ? nil : row.syncPayload()
                ))
                row.syncStatus = .syncing
            }
        }

        collect(ProjectLabel.self)
        collect(Tag.self)
        collect(ChecklistTemplate.self)
        collect(Project.self)
        collect(Photo.self)
        collect(ProjectTask.self)
        collect(Checklist.self)
        collect(ChecklistItem.self)
        collect(PhotoComment.self)
        collect(TaskComment.self)
        collect(Report.self)
        collect(BeforeAfterPair.self)
        collect(Page.self)
        collect(Measurement.self)

        try? modelContext.save()
        return mutations
    }

    /// Reconciles a push batch's acks: `applied` → `.synced` (unless re-edited
    /// mid-flight), `stale` → adopt the server row (the LWW winner), `rejected`
    /// → accept the refusal so it stops re-pushing.
    func applyAcks(_ acks: [MutationAck], pushed mutations: [SyncMutation]) {
        var pushedMs: [String: Int] = [:]
        for mutation in mutations {
            pushedMs["\(mutation.entity):\(mutation.id.uuidString)"] =
                Int(mutation.updatedAt.timeIntervalSince1970 * 1000)
        }
        for ack in acks {
            let key = "\(ack.entity):\(ack.id.uuidString)"
            switch ack.status {
            case "applied":
                SyncMappers.markResolved(entity: ack.entity, id: ack.id, pushedMs: pushedMs[key], force: false, in: modelContext)
            case "stale":
                if let server = ack.server {
                    SyncMappers.apply(entity: ack.entity, row: server, in: modelContext, lww: false)
                }
            case "rejected":
                SyncMappers.markResolved(entity: ack.entity, id: ack.id, pushedMs: pushedMs[key], force: true, in: modelContext)
            default:
                break
            }
        }
        try? modelContext.save()
    }

    /// Applies one pulled delta page (upsert by id, tombstones, parents first).
    func apply(changes: [String: [SyncRow]]) {
        SyncMappers.applyChanges(changes, in: modelContext)
        try? modelContext.save()
    }
}
