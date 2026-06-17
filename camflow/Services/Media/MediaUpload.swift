import Foundation
import SwiftData

/// Client-only outbox row for one photo/video's raw-bytes upload. **Not** a sync
/// entity (never pushed/pulled) — it tracks the ticket → PUT → commit pipeline so
/// uploads survive app suspend/relaunch. `MediaUploader` resolves the rest (org,
/// file, size, media type) from the referenced `Photo` at processing time, so
/// this stays minimal: enqueueing only needs the photo id.
@Model
final class MediaUpload {
    enum State: String, Codable {
        case pending // needs a ticket + PUT
        case uploading // background PUT in flight
        case committing // PUT done, /media/commit in flight
        case failed // errored; retried while `attempts` < max
    }

    @Attribute(.unique) var id: UUID
    var photoID: UUID
    // Optional raw string + computed enum (migration-safe pattern), though this
    // is a brand-new entity so NULL never occurs in practice.
    private var stateRaw: String?
    /// Storage object key returned by the upload ticket; needed by commit.
    var objectKey: String?
    var attempts: Int
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date

    var state: State {
        get { stateRaw.flatMap(State.init(rawValue:)) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    init(photoID: UUID) {
        self.id = UUID()
        self.photoID = photoID
        self.stateRaw = State.pending.rawValue
        self.objectKey = nil
        self.attempts = 0
        self.lastError = nil
        self.createdAt = .now
        self.updatedAt = .now
    }
}
