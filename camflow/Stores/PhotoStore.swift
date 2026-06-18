import Foundation
import CoreLocation
import SwiftData

/// Mutation layer for photos: writes image bytes to disk off-main, then
/// records the entity on the main context.
@MainActor
struct PhotoStore {
    let context: ModelContext

    @discardableResult
    func createPhoto(
        imageData: Data,
        capturedAt: Date = .now,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationAccuracyM: Double? = nil,
        locationFixAt: Date? = nil,
        isLocationSimulated: Bool = false,
        source: Photo.Source,
        project: Project?,
        author: OrgMember? = nil
    ) async throws -> Photo {
        let id = UUID()
        let fileName = "\(id.uuidString).jpg"
        let thumbnailFileName = "\(id.uuidString)_thumb.jpg"

        try await Task.detached(priority: .userInitiated) {
            try FileStorage.save(imageData, named: fileName, in: .photos)
            if let thumbnail = ImageProcessor.makeThumbnail(from: imageData) {
                try FileStorage.save(thumbnail, named: thumbnailFileName, in: .photos)
            }
        }.value

        let photo = Photo(
            fileName: fileName,
            thumbnailFileName: thumbnailFileName,
            capturedAt: capturedAt,
            latitude: latitude,
            longitude: longitude,
            locationAccuracyM: locationAccuracyM,
            locationFixAt: locationFixAt,
            isLocationSimulated: isLocationSimulated,
            source: source,
            project: project,
            author: author
        )
        photo.id = id
        context.insert(photo)
        enqueueUpload(for: photo)

        if let project {
            project.updatedAt = .now
        }
        return photo
    }

    /// Adopts a finished movie recording: moves the file into the store (no
    /// byte copy — 2 min of 1080p doesn't fit in memory), generates a poster
    /// thumbnail, then records the entity on the main context.
    @discardableResult
    func createVideo(
        tempURL: URL,
        capturedAt: Date = .now,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationAccuracyM: Double? = nil,
        locationFixAt: Date? = nil,
        isLocationSimulated: Bool = false,
        project: Project?,
        author: OrgMember? = nil
    ) async throws -> Photo {
        let id = UUID()
        let fileName = "\(id.uuidString).mov"
        let thumbnailFileName = "\(id.uuidString)_thumb.jpg"

        let duration = try await Task.detached(priority: .userInitiated) {
            let duration = await VideoProcessor.duration(of: tempURL)
            if let thumbnail = await VideoProcessor.makeThumbnail(forVideoAt: tempURL) {
                try FileStorage.save(thumbnail, named: thumbnailFileName, in: .photos)
            }
            try FileStorage.adopt(fileAt: tempURL, named: fileName, in: .photos)
            return duration
        }.value

        let photo = Photo(
            fileName: fileName,
            thumbnailFileName: thumbnailFileName,
            capturedAt: capturedAt,
            latitude: latitude,
            longitude: longitude,
            locationAccuracyM: locationAccuracyM,
            locationFixAt: locationFixAt,
            isLocationSimulated: isLocationSimulated,
            source: .camera,
            mediaType: .video,
            durationSeconds: duration,
            project: project,
            author: author
        )
        photo.id = id
        context.insert(photo)
        enqueueUpload(for: photo)

        if let project {
            project.updatedAt = .now
        }
        return photo
    }

    /// Imports a library photo, pulling capture date and GPS from EXIF.
    @discardableResult
    func importPhoto(imageData: Data, project: Project?, author: OrgMember? = nil) async throws -> Photo {
        let metadata = await Task.detached { ImageProcessor.metadata(from: imageData) }.value
        return try await createPhoto(
            imageData: imageData,
            capturedAt: metadata.capturedAt ?? .now,
            latitude: metadata.latitude,
            longitude: metadata.longitude,
            source: .imported,
            project: project,
            author: author
        )
    }

    /// Queues the photo's raw bytes for background upload to the media pipeline.
    /// Picked up by `MediaUploader` (no-op without a cloud session). Kept here so
    /// every capture/import path enqueues exactly once at the single write seam.
    private func enqueueUpload(for photo: Photo) {
        context.insert(MediaUpload(photoID: photo.id))
    }

    func touch(_ photo: Photo) {
        photo.updatedAt = .now
        photo.syncStatus = .local
    }

    func softDelete(_ photo: Photo) {
        photo.deletedAt = .now
        touch(photo)
        
    }

    @discardableResult
    func addComment(to photo: Photo, text: String, mentionIDs: [UUID], author: OrgMember?) -> PhotoComment {
        let comment = PhotoComment(text: text, mentionIDs: mentionIDs, author: author, photo: photo)
        context.insert(comment)
        NotificationStore(context: context).notifyPhotoComment(comment)
        touch(photo)
        return comment
    }

    func softDeleteComment(_ comment: PhotoComment) {
        comment.deletedAt = .now
        comment.updatedAt = .now
    }
}
