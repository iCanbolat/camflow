import SwiftUI

/// One captured-but-not-yet-saved item in a camera session. The capture screen
/// holds these in an array and only persists them to SwiftData on "Done".
///
/// Reference semantics (`@Observable` class) so edits made in the review screen
/// or annotation editor flow back into the array the capture screen owns.
@Observable
final class CapturedDraft: Identifiable {
    enum Media {
        /// Full-resolution JPEG, held in memory until submitted.
        case photo(imageData: Data)
        /// Finished recording on disk (a temp file); moved into the store on submit.
        case video(url: URL, duration: Double?)
    }

    let id = UUID()
    let media: Media
    /// Small image for the capture stack and review filmstrip.
    let thumbnail: UIImage
    let capturedAt: Date
    let latitude: Double?
    let longitude: Double?
    let source: Photo.Source
    var caption: String = ""
    /// Vector annotation document (JSON). Photos only — videos stay nil.
    var annotationData: Data?

    init(
        media: Media,
        thumbnail: UIImage,
        capturedAt: Date = .now,
        latitude: Double? = nil,
        longitude: Double? = nil,
        source: Photo.Source = .camera
    ) {
        self.media = media
        self.thumbnail = thumbnail
        self.capturedAt = capturedAt
        self.latitude = latitude
        self.longitude = longitude
        self.source = source
    }

    var isVideo: Bool {
        if case .video = media { return true }
        return false
    }

    /// Temp file backing a video draft, if any — used to clean up on discard.
    var videoURL: URL? {
        if case .video(let url, _) = media { return url }
        return nil
    }
}
