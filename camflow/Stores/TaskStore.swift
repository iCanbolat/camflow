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
        return task
    }

    func touch(_ task: ProjectTask) {
        task.updatedAt = .now
        task.syncStatus = .local
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
        touch(task)
        return comment
    }

    func softDeleteComment(_ comment: TaskComment) {
        comment.deletedAt = .now
        comment.updatedAt = .now
    }
}
