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

    /// Server-side media-pipeline state (mirrors the backend `processing_status`).
    /// Arrives via sync pull; the client never pushes it. `done` is the sane
    /// fallback for local-origin/legacy rows so they never show a processing
    /// spinner — display is always local-bytes-first regardless of this value.
    enum ProcessingStatus: String, Codable {
        case pending // row exists, no bytes uploaded yet
        case queued // raw bytes committed, processing job enqueued
        case processing
        case done
        case failed
    }

    /// Server-derived trustworthiness of the location/time stamp. Arrives via
    /// sync pull (graded at media commit); the client never pushes it. Defaults
    /// to `.unverified` so a stamp is never over-claimed for local/legacy rows.
    enum CaptureVerification: String, Codable {
        case verified // camera, fresh+accurate fix, not simulated, clock OK
        case unverified // imported, or missing/weak/stale location
        case flagged // simulated location or excessive clock skew
    }

    @Attribute(.unique) var id: UUID
    var capturedAt: Date
    var latitude: Double?
    var longitude: Double?
    // --- Capture evidence (pushed; the server grades it at commit) ---
    /// Horizontal accuracy (metres) of the fix used to stamp this capture.
    var locationAccuracyM: Double?
    /// When the GPS fix was actually obtained — staleness vs `capturedAt`.
    var locationFixAt: Date?
    /// Whether the OS reported the fix as software-simulated (mock detection).
    var isLocationSimulated: Bool = false
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
    // Optional raw string + computed enum: lightweight migration leaves the new
    // column NULL, and SwiftData crashes casting NULL into a non-optional enum.
    private var processingStatusRaw: String?

    // --- Capture verification (server-derived; arrives via pull, never pushed) ---
    private var captureVerificationRaw: String?
    /// `serverReceivedAt - capturedAt` in seconds (device-clock cross-check).
    var clockSkewSeconds: Double?
    /// HMAC sealing the capture record; tamper-evidence + watermark proof token.
    var captureSignature: String?
    /// Server clock at the moment the capture was committed/sealed.
    var serverReceivedAt: Date?

    var mediaType: MediaType {
        get { mediaTypeRaw.flatMap(MediaType.init(rawValue:)) ?? .photo }
        set { mediaTypeRaw = newValue.rawValue }
    }

    /// Server media-pipeline state; `.done` when unknown (local-origin/legacy).
    var processingStatus: ProcessingStatus {
        get { processingStatusRaw.flatMap(ProcessingStatus.init(rawValue:)) ?? .done }
        set { processingStatusRaw = newValue.rawValue }
    }

    /// Server verdict on the location/time stamp; `.unverified` when unknown.
    var captureVerification: CaptureVerification {
        get { captureVerificationRaw.flatMap(CaptureVerification.init(rawValue:)) ?? .unverified }
        set { captureVerificationRaw = newValue.rawValue }
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
        locationAccuracyM: Double? = nil,
        locationFixAt: Date? = nil,
        isLocationSimulated: Bool = false,
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
        self.locationAccuracyM = locationAccuracyM
        self.locationFixAt = locationFixAt
        self.isLocationSimulated = isLocationSimulated
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
