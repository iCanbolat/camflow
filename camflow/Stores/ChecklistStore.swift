import Foundation
import SwiftData

@MainActor
struct ChecklistStore {
    let context: ModelContext

    /// Creates a checklist, copying items from a template when given.
    @discardableResult
    func create(
        name: String,
        template: ChecklistTemplate? = nil,
        assignee: OrgMember? = nil,
        project: Project
    ) -> Checklist {
        let checklist = Checklist(name: name, templateID: template?.id, project: project)
        checklist.assignee = assignee
        context.insert(checklist)
        if let template {
            for (index, title) in template.itemTitles.enumerated() {
                let item = ChecklistItem(title: title, sortOrder: index, checklist: checklist)
                context.insert(item)
            }
        }
        project.updatedAt = .now
        return checklist
    }

    func touch(_ checklist: Checklist) {
        checklist.updatedAt = .now
        checklist.syncStatus = .local
    }

    func softDelete(_ checklist: Checklist) {
        checklist.deletedAt = .now
        touch(checklist)
    }

    @discardableResult
    func addItem(to checklist: Checklist, title: String) -> ChecklistItem {
        let nextOrder = (checklist.items.map(\.sortOrder).max() ?? -1) + 1
        let item = ChecklistItem(title: title, sortOrder: nextOrder, checklist: checklist)
        context.insert(item)
        touch(checklist)
        return item
    }

    func toggleItem(_ item: ChecklistItem) {
        item.isDone.toggle()
        item.completedAt = item.isDone ? .now : nil
        item.updatedAt = .now
        if let checklist = item.checklist {
            touch(checklist)
        }
    }

    func softDeleteItem(_ item: ChecklistItem) {
        item.deletedAt = .now
        item.updatedAt = .now
    }

    // MARK: - Templates

    @discardableResult
    func createTemplate(name: String, itemTitles: [String]) -> ChecklistTemplate {
        let template = ChecklistTemplate(name: name, itemTitles: itemTitles)
        context.insert(template)
        return template
    }

    func touchTemplate(_ template: ChecklistTemplate) {
        template.updatedAt = .now
        template.syncStatus = .local
    }

    func softDeleteTemplate(_ template: ChecklistTemplate) {
        template.deletedAt = .now
        touchTemplate(template)
    }
}
