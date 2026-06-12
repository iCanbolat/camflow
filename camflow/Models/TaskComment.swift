import Foundation
import SwiftData

/// A comment on a task's discussion thread. Mentions are stored both inline
/// in the text ("@Full Name") and as member IDs so a future notification
/// system can fan out without parsing.
@Model
final class TaskComment {
    @Attribute(.unique) var id: UUID
    var text: String
    /// Members mentioned in this comment.
    var mentionIDs: [UUID]

    var author: OrgMember?
    var task: ProjectTask?

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(text: String, mentionIDs: [UUID] = [], author: OrgMember? = nil, task: ProjectTask? = nil) {
        self.id = UUID()
        self.text = text
        self.mentionIDs = mentionIDs
        self.author = author
        self.task = task
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }
}
