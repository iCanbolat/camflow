import Foundation
import SwiftData

/// A single to-do on a project. Completion is timestamped automatically.
/// Named `ProjectTask` to avoid clashing with Swift Concurrency's `Task`.
@Model
final class ProjectTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var note: String
    var dueDate: Date?
    var completedAt: Date?
    /// Evidence photos attached to this task.
    var attachedPhotoIDs: [UUID]

    var project: Project?
    /// Team member responsible for this task.
    var assignee: OrgMember?

    @Relationship(deleteRule: .cascade, inverse: \TaskComment.task)
    var comments: [TaskComment] = []

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(title: String, note: String = "", dueDate: Date? = nil, project: Project? = nil) {
        self.id = UUID()
        self.title = title
        self.note = note
        self.dueDate = dueDate
        self.completedAt = nil
        self.attachedPhotoIDs = []
        self.project = project
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }

    var isCompleted: Bool { completedAt != nil }

    var activeComments: [TaskComment] {
        comments
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var isOverdue: Bool {
        guard let dueDate, !isCompleted else { return false }
        return dueDate < Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
            && dueDate < .now
    }
}

/// Reusable checklist blueprint (e.g. "Roof Inspection", "Final Walkthrough").
@Model
final class ChecklistTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var itemTitles: [String]

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(name: String, itemTitles: [String] = []) {
        self.id = UUID()
        self.name = name
        self.itemTitles = itemTitles
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }
}

/// Checklist instance attached to a project, optionally created from a template.
@Model
final class Checklist {
    @Attribute(.unique) var id: UUID
    var name: String
    var templateID: UUID?

    var project: Project?
    /// Team member responsible for this checklist.
    var assignee: OrgMember?

    @Relationship(deleteRule: .cascade, inverse: \ChecklistItem.checklist)
    var items: [ChecklistItem] = []

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(name: String, templateID: UUID? = nil, project: Project? = nil) {
        self.id = UUID()
        self.name = name
        self.templateID = templateID
        self.project = project
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }

    var sortedItems: [ChecklistItem] {
        items
            .filter { $0.deletedAt == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var progress: Double {
        let active = sortedItems
        guard !active.isEmpty else { return 0 }
        return Double(active.filter(\.isDone).count) / Double(active.count)
    }
}

@Model
final class ChecklistItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var isDone: Bool
    var completedAt: Date?
    /// Optional evidence photo.
    var photoID: UUID?
    var sortOrder: Int

    var checklist: Checklist?

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(title: String, sortOrder: Int, checklist: Checklist? = nil) {
        self.id = UUID()
        self.title = title
        self.isDone = false
        self.completedAt = nil
        self.photoID = nil
        self.sortOrder = sortOrder
        self.checklist = checklist
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }
}
