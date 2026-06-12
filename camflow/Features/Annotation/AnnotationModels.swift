import Foundation
import CoreGraphics

/// Vector annotation document stored in `Photo.annotationData` as JSON.
/// The original image is never modified; shapes are baked into pixels
/// only when exporting or building reports.
struct AnnotationDocument: Codable, Equatable {
    var shapes: [AnnotationShape] = []

    static func decode(_ data: Data?) -> AnnotationDocument {
        guard let data,
              let document = try? JSONDecoder().decode(AnnotationDocument.self, from: data) else {
            return AnnotationDocument()
        }
        return document
    }

    func encoded() -> Data? {
        guard !shapes.isEmpty else { return nil }
        return try? JSONEncoder().encode(self)
    }
}

/// One drawn shape. All coordinates are normalized to [0, 1] relative to the
/// image so annotations render correctly at any display size.
struct AnnotationShape: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case freehand
        case arrow
        case rectangle
        case ellipse
        case text
    }

    var id = UUID()
    var kind: Kind
    var colorHex: String
    /// freehand: the path · arrow: [start, end] · rectangle/ellipse: [corner, corner] · text: [anchor]
    var points: [CGPoint]
    /// Stroke width as a fraction of image width.
    var lineWidth: Double = 0.006
    var text: String?
    /// Font size as a fraction of image width.
    var fontScale: Double = 0.045
}
