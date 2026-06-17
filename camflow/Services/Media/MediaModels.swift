import Foundation

// Wire models for the media pipeline (`api/src/media/*`). All `nonisolated` +
// `Sendable` so they cross the networking actors.

// MARK: - Upload ticket

nonisolated struct UploadTicketBody: Encodable, Sendable {
    let organizationId: UUID
    let photoId: UUID
    let mediaType: String // "photo" | "video"
    let ext: String
    let byteSize: Int
    let contentType: String?
}

/// `POST /media/upload-ticket` → a signed direct-upload target (no bytes here).
nonisolated struct UploadTicketDTO: Decodable, Sendable {
    let uploadUrl: String
    let method: String
    let objectKey: String
    let maxBytes: Int
    let expiresAt: Date
}

// MARK: - Commit

nonisolated struct CommitUploadBody: Encodable, Sendable {
    let organizationId: UUID
    let photoId: UUID
    let objectKey: String
    let mediaType: String
    let projectId: UUID?
}

nonisolated struct CommitUploadDTO: Decodable, Sendable {
    let photoId: UUID
    let status: String
}

/// Body for org-scoped media actions that carry no other payload
/// (`POST /media/:id/reprocess`).
nonisolated struct MediaScopeBody: Encodable, Sendable {
    let organizationId: UUID
}

// MARK: - Download

/// `GET /media/:id/urls` → signed CDN URLs for the processed variants (each may
/// be `null` until the worker finishes).
nonisolated struct MediaURLsDTO: Decodable, Sendable {
    let photoId: UUID
    let status: String
    let processed: String?
    let thumbnail: String?
    let watermarked: String?
}
