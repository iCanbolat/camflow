import Foundation
import SwiftData

/// Creates and mutates `AppNotification` rows. Fan-out runs at the moment an
/// event happens (assignment, comment, mention) and never notifies the actor
/// about their own action. Read/delete state is per-item.
@MainActor
struct NotificationStore {
    let context: ModelContext

    // MARK: - Read state

    func touch(_ notification: AppNotification) {
        notification.updatedAt = .now
        notification.syncStatus = .local
    }

    func markRead(_ notification: AppNotification) {
        guard !notification.isRead else { return }
        notification.isRead = true
        notification.readAt = .now
        touch(notification)
    }

    func toggleRead(_ notification: AppNotification) {
        notification.isRead.toggle()
        notification.readAt = notification.isRead ? .now : nil
        touch(notification)
    }

    func markAllRead(_ notifications: [AppNotification]) {
        for notification in notifications { markRead(notification) }
    }

    func softDelete(_ notification: AppNotification) {
        notification.deletedAt = .now
        touch(notification)
    }

    // MARK: - Fan-out

    func notifyTaskAssigned(_ task: ProjectTask, assignee: OrgMember?, by actor: OrgMember?) {
        guard let assignee, assignee.id != actor?.id else { return }
        guard !hasActive(kind: .taskAssigned, taskID: task.id, recipientID: assignee.id) else { return }
        let notification = AppNotification(
            kind: .taskAssigned,
            recipient: assignee,
            actor: actor,
            task: task,
            project: task.project
        )
        context.insert(notification)
    }

    func notifyChecklistAssigned(_ checklist: Checklist, assignee: OrgMember?, by actor: OrgMember?) {
        guard let assignee, assignee.id != actor?.id else { return }
        guard !hasActive(kind: .checklistAssigned, checklistID: checklist.id, recipientID: assignee.id) else { return }
        let notification = AppNotification(
            kind: .checklistAssigned,
            recipient: assignee,
            actor: actor,
            checklist: checklist,
            project: checklist.project
        )
        context.insert(notification)
    }

    /// Fans a freshly created comment out to mentioned members and to the task's
    /// assignee, excluding the comment's own author.
    func notifyComment(_ comment: TaskComment) {
        guard let task = comment.task else { return }
        let author = comment.author
        let candidates = task.project?.organization?.activeMembers ?? []

        var notifiedIDs: Set<UUID> = []
        for memberID in comment.mentionIDs where memberID != author?.id {
            guard let member = candidates.first(where: { $0.id == memberID }) else { continue }
            context.insert(AppNotification(
                kind: .mention,
                recipient: member,
                actor: author,
                task: task,
                project: task.project,
                bodySnippet: comment.text
            ))
            notifiedIDs.insert(memberID)
        }

        if let assignee = task.assignee,
           assignee.id != author?.id,
           !notifiedIDs.contains(assignee.id) {
            context.insert(AppNotification(
                kind: .comment,
                recipient: assignee,
                actor: author,
                task: task,
                project: task.project,
                bodySnippet: comment.text
            ))
        }
    }

    /// Fans a freshly created photo/video comment out to mentioned members,
    /// excluding the author. Photos have no assignee, so (unlike tasks) there's
    /// no comment-to-assignee fan-out — only mentions. Members are looked up by
    /// id rather than via the photo's project, so mentions work on unassigned
    /// photos too (the composer's candidates come from the active org).
    func notifyPhotoComment(_ comment: PhotoComment) {
        guard let photo = comment.photo else { return }
        let author = comment.author

        for memberID in comment.mentionIDs where memberID != author?.id {
            guard let member = member(id: memberID) else { continue }
            context.insert(AppNotification(
                kind: .mention,
                recipient: member,
                actor: author,
                photo: photo,
                project: photo.project,
                bodySnippet: comment.text
            ))
        }
    }

    private func member(id: UUID) -> OrgMember? {
        let descriptor = FetchDescriptor<OrgMember>(
            predicate: #Predicate { $0.id == id && $0.deletedAt == nil }
        )
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Dedupe

    /// Whether a non-deleted notification of this kind already exists for the
    /// given source + recipient (so re-saving an assignment doesn't pile up).
    private func hasActive(
        kind: AppNotification.Kind,
        taskID: UUID? = nil,
        checklistID: UUID? = nil,
        recipientID: UUID
    ) -> Bool {
        let descriptor = FetchDescriptor<AppNotification>(predicate: #Predicate { $0.deletedAt == nil })
        let existing = (try? context.fetch(descriptor)) ?? []
        return existing.contains {
            $0.kind == kind
                && $0.recipient?.id == recipientID
                && (taskID == nil || $0.task?.id == taskID)
                && (checklistID == nil || $0.checklist?.id == checklistID)
        }
    }
}
