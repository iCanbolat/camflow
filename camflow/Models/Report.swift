import Foundation
import SwiftData

/// A generated PDF photo report for a project.
@Model
final class Report {
    enum Layout: String, Codable {
        case onePerPage
        case twoPerPage
        case fourPerPage
    }

    @Attribute(.unique) var id: UUID
    var title: String
    /// Ordered photo selection.
    var photoIDs: [UUID]
    /// Per-photo notes keyed by photo id.
    var photoNotes: [UUID: String]
    var layout: Layout
    /// Appends a checklist summary page after the photo pages.
    var includesChecklistSummary: Bool = false
    /// Generated PDF inside `FileStorage.reportsDirectory`, nil until exported.
    var pdfFileName: String?

    var project: Project?

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(title: String, photoIDs: [UUID] = [], layout: Layout = .twoPerPage, project: Project? = nil) {
        self.id = UUID()
        self.title = title
        self.photoIDs = photoIDs
        self.photoNotes = [:]
        self.layout = layout
        self.pdfFileName = nil
        self.project = project
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }
}

/// A saved before/after photo pairing for transformation exports.
@Model
final class BeforeAfterPair {
    enum Layout: String, Codable {
        case sideBySide
        case stacked
    }

    @Attribute(.unique) var id: UUID
    var beforePhotoID: UUID
    var afterPhotoID: UUID
    var layout: Layout

    var project: Project?

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(beforePhotoID: UUID, afterPhotoID: UUID, layout: Layout = .sideBySide, project: Project? = nil) {
        self.id = UUID()
        self.beforePhotoID = beforePhotoID
        self.afterPhotoID = afterPhotoID
        self.layout = layout
        self.project = project
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }
}
