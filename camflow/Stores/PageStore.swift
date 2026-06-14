import Foundation
import SwiftData

@MainActor
struct PageStore {
    let context: ModelContext

    @discardableResult
    func create(
        title: String,
        document: PageDocument,
        project: Project,
        author: OrgMember? = nil
    ) -> Page {
        let page = Page(
            title: title,
            document: document,
            sortOrder: project.activePages.count,
            project: project,
            author: author
        )
        context.insert(page)
        project.updatedAt = .now
        return page
    }

    /// Persists edits to a page's title and block document.
    func update(_ page: Page, title: String, document: PageDocument) {
        page.title = title
        page.contentData = document.encoded()
        touch(page)
    }

    func touch(_ page: Page) {
        page.updatedAt = .now
        page.syncStatus = .local
    }

    func softDelete(_ page: Page) {
        if let fileName = page.pdfFileName {
            FileStorage.delete(fileName, in: .pages)
        }
        page.deletedAt = .now
        touch(page)
    }

    /// Reassigns `sortOrder` to match the given display order.
    func reorder(_ pages: [Page]) {
        for (index, page) in pages.enumerated() where page.sortOrder != index {
            page.sortOrder = index
            touch(page)
        }
    }
}
