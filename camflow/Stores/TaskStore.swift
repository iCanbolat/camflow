import Foundation
import SwiftData

@MainActor
struct TaskStore {
    let context: ModelContext

    @discardableResult
    func create(
        title: String,
        note: String = "",
        dueDate: Date? = nil,
        assignee: OrgMember? = nil,
        project: Project
    ) -> ProjectTask {
        let task = ProjectTask(title: title, note: note, dueDate: dueDate, project: project)
        task.assignee = assignee
        context.insert(task)
        project.updatedAt = .now
        save()
        return task
    }

    func touch(_ task: ProjectTask) {
        task.updatedAt = .now
        task.syncStatus = .local
        save()
    }

    /// Persists pending changes immediately so relationship-driven views
    /// (e.g. `project.tasks`) refresh right away instead of waiting for the
    /// next autosave, whose timing is non-deterministic.
    private func save() {
        try? context.save()
    }

    /// Completion is timestamped automatically; toggling back clears it.
    func toggleCompletion(_ task: ProjectTask) {
        task.completedAt = task.isCompleted ? nil : .now
        touch(task)
    }

    func softDelete(_ task: ProjectTask) {
        task.deletedAt = .now
        touch(task)
    }

    @discardableResult
    func addComment(to task: ProjectTask, text: String, mentionIDs: [UUID], author: OrgMember?) -> TaskComment {
        let comment = TaskComment(text: text, mentionIDs: mentionIDs, author: author, task: task)
        context.insert(comment)
        NotificationStore(context: context).notifyComment(comment)
        touch(task)
        return comment
    }

    func softDeleteComment(_ comment: TaskComment) {
        comment.deletedAt = .now
        comment.updatedAt = .now
        save()
    }
}
