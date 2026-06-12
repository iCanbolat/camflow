import Foundation
import SwiftData

@MainActor
struct ReportStore {
    let context: ModelContext

    @discardableResult
    func create(
        title: String,
        photoIDs: [UUID],
        photoNotes: [UUID: String],
        layout: Report.Layout,
        includesChecklistSummary: Bool,
        project: Project
    ) -> Report {
        let report = Report(title: title, photoIDs: photoIDs, layout: layout, project: project)
        report.photoNotes = photoNotes
        report.includesChecklistSummary = includesChecklistSummary
        context.insert(report)
        project.updatedAt = .now
        return report
    }

    func touch(_ report: Report) {
        report.updatedAt = .now
        report.syncStatus = .local
    }

    func softDelete(_ report: Report) {
        if let fileName = report.pdfFileName {
            FileStorage.delete(fileName, in: .reports)
        }
        report.deletedAt = .now
        touch(report)
    }
}

@MainActor
struct BeforeAfterStore {
    let context: ModelContext

    @discardableResult
    func create(
        beforePhotoID: UUID,
        afterPhotoID: UUID,
        layout: BeforeAfterPair.Layout,
        project: Project
    ) -> BeforeAfterPair {
        let pair = BeforeAfterPair(
            beforePhotoID: beforePhotoID,
            afterPhotoID: afterPhotoID,
            layout: layout,
            project: project
        )
        context.insert(pair)
        project.updatedAt = .now
        return pair
    }

    func touch(_ pair: BeforeAfterPair) {
        pair.updatedAt = .now
        pair.syncStatus = .local
    }

    func softDelete(_ pair: BeforeAfterPair) {
        pair.deletedAt = .now
        touch(pair)
    }
}
