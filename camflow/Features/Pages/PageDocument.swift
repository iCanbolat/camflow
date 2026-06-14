import Foundation

/// The block document stored in `Page.contentData` as JSON. Mirrors the
/// `AnnotationDocument` pattern: a flat `Codable` struct with `decode`/`encoded`
/// helpers that never throw to the caller.
struct PageDocument: Codable, Equatable {
    var blocks: [PageBlock] = []

    static func decode(_ data: Data) -> PageDocument {
        guard !data.isEmpty,
              let document = try? JSONDecoder().decode(PageDocument.self, from: data) else {
            return PageDocument()
        }
        return document
    }

    func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}

/// One block in a `Page`. Following the codebase's `AnnotationShape` style, all
/// payloads live on a single struct and only the fields relevant to `kind` are
/// populated.
struct PageBlock: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case heading
        case paragraph
        case bulletList
        case numberedList
        case checklist
        case divider
        case photo
        case photoGrid
    }

    var id = UUID()
    var kind: Kind

    /// heading / paragraph rich text.
    var text: AttributedString?
    /// Heading level 1…3.
    var headingLevel: Int?
    /// bullet / numbered list items.
    var listItems: [AttributedString]?
    /// checklist rows.
    var checklistItems: [PageChecklistItem]?
    /// photo (single) · photoGrid (many).
    var photoIDs: [UUID]?
    /// Caption shown under a photo / photo grid.
    var caption: String?
    /// Rendered width for a single photo block.
    var photoSize: PagePhotoSize?
    /// Square crop vs. original aspect ratio.
    var squareCrop: Bool?
    /// Columns for a photo grid (2 or 3).
    var columns: Int?

    init(kind: Kind) {
        self.kind = kind
    }
}

extension PageBlock {
    /// A fresh block of the given kind with sensible defaults per payload.
    static func make(_ kind: Kind) -> PageBlock {
        var block = PageBlock(kind: kind)
        switch kind {
        case .heading:
            block.text = AttributedString("")
            block.headingLevel = 2
        case .paragraph:
            block.text = AttributedString("")
        case .bulletList, .numberedList:
            block.listItems = [AttributedString("")]
        case .checklist:
            block.checklistItems = [PageChecklistItem(text: "", isDone: false)]
        case .divider:
            break
        case .photo:
            block.photoIDs = []
            block.photoSize = .full
            block.squareCrop = false
        case .photoGrid:
            block.photoIDs = []
            block.columns = 2
            block.squareCrop = true
        }
        return block
    }
}

struct PageChecklistItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var text: String
    var isDone: Bool

    init(text: String = "", isDone: Bool = false) {
        self.text = text
        self.isDone = isDone
    }
}

enum PagePhotoSize: String, Codable, CaseIterable {
    case small
    case medium
    case full

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .full: return "Full Width"
        }
    }

    /// Fraction of the available content width.
    var widthFraction: Double {
        switch self {
        case .small: return 0.4
        case .medium: return 0.65
        case .full: return 1.0
        }
    }
}
