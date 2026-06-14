import Foundation

/// Built-in (non-AI) starter layouts shown in the "New Page" chooser — the
/// offline stand-in for CompanyCam's "Report / Daily Log / Summary" presets.
/// Each returns a prebuilt `PageDocument`; templates carry structure only,
/// never job-specific photos.
enum PageTemplate: String, CaseIterable, Identifiable {
    case blank
    case photoReport
    case dailyLog
    case siteInspection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank: return "Blank"
        case .photoReport: return "Photo Report"
        case .dailyLog: return "Daily Log"
        case .siteInspection: return "Site Inspection"
        }
    }

    var subtitle: String {
        switch self {
        case .blank: return "Start from an empty page"
        case .photoReport: return "Heading, summary, and a photo grid"
        case .dailyLog: return "Date, work completed, tasks, and photos"
        case .siteInspection: return "Inspection checklist with notes and photos"
        }
    }

    var systemImage: String {
        switch self {
        case .blank: return "doc"
        case .photoReport: return "doc.richtext"
        case .dailyLog: return "calendar.day.timeline.left"
        case .siteInspection: return "checklist"
        }
    }

    /// Default title for a page created from this template.
    var defaultPageTitle: String {
        switch self {
        case .blank: return "Untitled Page"
        case .photoReport: return "Photo Report"
        case .dailyLog: return "Daily Log " + Self.shortDate.string(from: .now)
        case .siteInspection: return "Site Inspection"
        }
    }

    func document() -> PageDocument {
        switch self {
        case .blank:
            return PageDocument(blocks: [.make(.paragraph)])

        case .photoReport:
            return PageDocument(blocks: [
                heading("Photo Report", level: 1),
                paragraph("Overview of the work completed on site."),
                divider(),
                heading("Photos", level: 2),
                photoGrid(),
            ])

        case .dailyLog:
            return PageDocument(blocks: [
                heading("Daily Log", level: 1),
                paragraph("Date: " + Self.longDate.string(from: .now)),
                divider(),
                heading("Work Completed", level: 2),
                paragraph(""),
                heading("Open Items", level: 2),
                checklist(["", ""]),
                heading("Photos", level: 2),
                photoGrid(),
            ])

        case .siteInspection:
            return PageDocument(blocks: [
                heading("Site Inspection", level: 1),
                paragraph("Date: " + Self.longDate.string(from: .now)),
                divider(),
                heading("Checklist", level: 2),
                checklist([
                    "Site access and safety",
                    "Materials on site",
                    "Workmanship",
                    "Cleanup",
                ]),
                heading("Notes", level: 2),
                paragraph(""),
                heading("Photos", level: 2),
                photoGrid(),
            ])
        }
    }

    // MARK: - Block builders

    private func heading(_ string: String, level: Int) -> PageBlock {
        var block = PageBlock.make(.heading)
        block.text = AttributedString(string)
        block.headingLevel = level
        return block
    }

    private func paragraph(_ string: String) -> PageBlock {
        var block = PageBlock.make(.paragraph)
        block.text = AttributedString(string)
        return block
    }

    private func checklist(_ items: [String]) -> PageBlock {
        var block = PageBlock.make(.checklist)
        block.checklistItems = items.map { PageChecklistItem(text: $0, isDone: false) }
        return block
    }

    private func divider() -> PageBlock {
        PageBlock.make(.divider)
    }

    private func photoGrid() -> PageBlock {
        PageBlock.make(.photoGrid)
    }

    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let longDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter
    }()
}
