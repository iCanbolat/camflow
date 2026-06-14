import Foundation
import SwiftData

@Model
final class Photo {
    enum Source: String, Codable {
        case camera
        case imported
    }

    enum MediaType: String, Codable {
        case photo
        case video
    }

    @Attribute(.unique) var id: UUID
    var capturedAt: Date
    var latitude: Double?
    var longitude: Double?
    /// Original media file name inside `FileStorage.photosDirectory` — `.jpg` for photos, `.mov` for videos.
    var fileName: String
    /// Downscaled thumbnail file name inside `FileStorage.photosDirectory` (always JPEG, also for videos).
    var thumbnailFileName: String
    var caption: String
    /// Vector annotation document (JSON) — rendered onto pixels only at export. Always nil for videos.
    var annotationData: Data?
    var source: Source
    // Stored as an optional raw string: lightweight migration leaves existing
    // rows NULL, and SwiftData crashes casting NULL into a non-optional enum.
    private var mediaTypeRaw: String?
    /// Playback length; nil for photos.
    var durationSeconds: Double?

    var mediaType: MediaType {
        get { mediaTypeRaw.flatMap(MediaType.init(rawValue:)) ?? .photo }
        set { mediaTypeRaw = newValue.rawValue }
    }

    var project: Project?

    /// The member who captured (or imported) this photo. Optional to-one with no
    /// inverse — same pattern as `TaskComment.author`; existing rows migrate as NULL.
    var author: OrgMember?

    var tags: [Tag] = []

    @Relationship(deleteRule: .cascade, inverse: \PhotoComment.photo)
    var comments: [PhotoComment] = []

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(
        fileName: String,
        thumbnailFileName: String,
        capturedAt: Date = .now,
        latitude: Double? = nil,
        longitude: Double? = nil,
        caption: String = "",
        source: Source = .camera,
        mediaType: MediaType = .photo,
        durationSeconds: Double? = nil,
        project: Project? = nil,
        author: OrgMember? = nil
    ) {
        self.id = UUID()
        self.fileName = fileName
        self.thumbnailFileName = thumbnailFileName
        self.capturedAt = capturedAt
        self.latitude = latitude
        self.longitude = longitude
        self.caption = caption
        self.annotationData = nil
        self.source = source
        self.mediaTypeRaw = mediaType.rawValue
        self.durationSeconds = durationSeconds
        self.project = project
        self.author = author
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }
}

extension Photo {
    var isVideo: Bool { mediaType == .video }

    /// Non-deleted comments, oldest-first (matches `ProjectTask.activeComments`).
    var activeComments: [PhotoComment] {
        comments
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// "m:ss" badge text for grid cells and the viewer info bar.
    var formattedDuration: String? {
        guard let durationSeconds else { return nil }
        return Duration.seconds(durationSeconds).formatted(.time(pattern: .minuteSecond))
    }
}
