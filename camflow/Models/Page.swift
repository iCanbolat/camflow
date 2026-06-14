import Foundation
import SwiftData

/// A rich block-based project note ("Page"): an ordered list of typed blocks
/// (headings, text, lists, checklists, dividers, photos) stored as JSON in
/// `contentData`. Photos are referenced by UUID inside the blocks — the bytes
/// stay in `FileStorage.photos`, mirroring `Report.photoIDs`.
@Model
final class Page {
    @Attribute(.unique) var id: UUID
    var title: String
    /// JSON-encoded `PageDocument` (the ordered blocks).
    var contentData: Data
    /// Display order within the project.
    var sortOrder: Int
    /// Generated PDF inside `FileStorage.pages`, nil until exported.
    var pdfFileName: String?

    var project: Project?
    /// Who created the page (mirrors `Photo.author`).
    var author: OrgMember?

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(
        title: String,
        document: PageDocument = PageDocument(),
        sortOrder: Int = 0,
        project: Project? = nil,
        author: OrgMember? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.contentData = document.encoded()
        self.sortOrder = sortOrder
        self.pdfFileName = nil
        self.project = project
        self.author = author
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }
}

extension Page {
    /// Decodes the stored block document.
    var document: PageDocument {
        PageDocument.decode(contentData)
    }
}
