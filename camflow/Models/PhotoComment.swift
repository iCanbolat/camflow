import Foundation
import SwiftData

/// A comment on a photo or video, independent of any task. Mentions are stored
/// both inline in the text ("@Full Name") and as member IDs so the notification
/// system can fan out without parsing. Mirrors `TaskComment`.
@Model
final class PhotoComment {
    @Attribute(.unique) var id: UUID
    var text: String
    /// Members mentioned in this comment.
    var mentionIDs: [UUID]

    var author: OrgMember?
    var photo: Photo?

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(text: String, mentionIDs: [UUID] = [], author: OrgMember? = nil, photo: Photo? = nil) {
        self.id = UUID()
        self.text = text
        self.mentionIDs = mentionIDs
        self.author = author
        self.photo = photo
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }
}
