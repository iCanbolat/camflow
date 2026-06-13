import Foundation
import SwiftData

/// A notification addressed to a single org member, created ("fanned out") when
/// a relevant event happens: a task/checklist assignment, an @mention, or a
/// comment on a task they're assigned to. Persisted (per-item read/delete) and
/// sync-ready like every other model. Named `AppNotification` to avoid clashing
/// with `Foundation.Notification`.
@Model
final class AppNotification {
    enum Kind: String, Codable {
        case taskAssigned
        case checklistAssigned
        case mention
        case comment
    }

    @Attribute(.unique) var id: UUID
    // Optional raw string + computed enum: lightweight migration leaves new
    // columns NULL, and SwiftData crashes casting NULL into a non-optional enum.
    private var kindRaw: String?

    var kind: Kind {
        get { kindRaw.flatMap(Kind.init(rawValue:)) ?? .comment }
        set { kindRaw = newValue.rawValue }
    }

    /// The member this notification is for.
    var recipient: OrgMember?
    /// The member who triggered it (comment author); `nil` for assignments.
    var actor: OrgMember?
    /// Navigation target / display source for task-related kinds.
    var task: ProjectTask?
    /// Source for checklist assignments.
    var checklist: Checklist?
    /// Navigation fallback (also set for assignments).
    var project: Project?
    /// Snapshot of the comment text for `.mention` / `.comment`.
    var bodySnippet: String

    var isRead: Bool
    var readAt: Date?

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(
        kind: Kind,
        recipient: OrgMember?,
        actor: OrgMember? = nil,
        task: ProjectTask? = nil,
        checklist: Checklist? = nil,
        project: Project? = nil,
        bodySnippet: String = "",
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.recipient = recipient
        self.actor = actor
        self.task = task
        self.checklist = checklist
        self.project = project
        self.bodySnippet = bodySnippet
        self.isRead = false
        self.readAt = nil
        self.createdAt = createdAt
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }
}
