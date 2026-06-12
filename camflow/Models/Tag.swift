import Foundation
import SwiftData

/// Photo tag — categorizes photos within and across projects.
@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String

    @Relationship(inverse: \Photo.tags)
    var photos: [Photo] = []

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(name: String, colorHex: String) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }
}

/// Project status label (Active, Completed, On Hold, …) — user defined.
@Model
final class ProjectLabel {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var sortOrder: Int

    @Relationship(inverse: \Project.label)
    var projects: [Project] = []

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(name: String, colorHex: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }
}
