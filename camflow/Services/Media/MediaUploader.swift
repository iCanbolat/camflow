import Foundation
import SwiftData

/// Drives raw-media uploads through the backend pipeline: **ticket → PUT → commit**.
/// The PUT runs on a background `URLSession` so a transfer survives app suspend
/// (and, with the Phase 4 app-delegate hook, relaunch). Ticket/commit are normal
/// authenticated JSON calls. Work is persisted in `MediaUpload` rows so a crash
/// or relaunch resumes cleanly; `MediaUploader` reads everything else (org, file,
/// size, media type) from the referenced `Photo`.
@MainActor
final class MediaUploader: NSObject {
    private let api: APIClient
    private let modelContext: ModelContext
    private let tokens: TokenStore

    private static let maxAttempts = 5
    private static let sessionIdentifier = "app.camflow.media-upload"

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    init(api: APIClient, context: ModelContext, tokens: TokenStore) {
        self.api = api
        self.modelContext = context
        self.tokens = tokens
        super.init()
    }

    /// Starts/resumes every eligible upload. Cheap to call repeatedly (launch,
    /// foreground, post-capture, after a sync). No-op without a cloud session.
    func processPending() async {
        guard await tokens.hasSession else { return }
        _ = session // ensure the background session is live to receive callbacks

        // Reconcile rows left `.uploading` by a previous run with no live task.
        let live = Set(await session.allTasks.compactMap { $0.taskDescription })
        let uploads = (try? modelContext.fetch(FetchDescriptor<MediaUpload>())) ?? []
        for upload in uploads where upload.state == .uploading && !live.contains(upload.id.uuidString) {
            upload.state = .pending
        }
        try? modelContext.save()

        for upload in uploads {
            switch upload.state {
            case .pending:
                await start(upload)
            case .failed where upload.attempts < Self.maxAttempts:
                await start(upload)
            case .committing:
                await commit(upload) // PUT finished before; finish the commit
            case .failed, .uploading:
                break
            }
        }
    }

    // MARK: - Pipeline

    private func start(_ upload: MediaUpload) async {
        guard let photo = fetchPhoto(upload.photoID), photo.deletedAt == nil else {
            modelContext.delete(upload)
            try? modelContext.save()
            return
        }
        // The photo row must already exist server-side before we commit media:
        // otherwise `/media/commit`'s insert wins Last-Write-Wins and clobbers the
        // metadata the sync push is about to send. Wait until the row is synced.
        guard photo.syncStatus == .synced else { return }
        guard let orgID = photo.project?.organization?.id else {
            return // org not resolvable yet (e.g. unassigned/project still syncing); retry later
        }
        let fileURL = FileStorage.url(for: photo.fileName, in: .photos)
        guard let size = fileSize(fileURL), size > 0 else {
            modelContext.delete(upload) // bytes gone (purged/never written); nothing to send
            try? modelContext.save()
            return
        }

        let ext = (photo.fileName as NSString).pathExtension.lowercased()
        let mediaType = photo.isVideo ? "video" : "photo"
        let contentType = contentType(ext: ext, isVideo: photo.isVideo)
        do {
            let body = UploadTicketBody(
                organizationId: orgID,
                photoId: photo.id,
                mediaType: mediaType,
                ext: ext.isEmpty ? "bin" : ext,
                byteSize: Int(size),
                contentType: contentType
            )
            let ticket: UploadTicketDTO = try await api.send(.post("/media/upload-ticket", json: body))
            guard let url = URL(string: ticket.uploadUrl) else {
                markFailed(upload, "Invalid upload URL.")
                return
            }
            upload.objectKey = ticket.objectKey
            upload.state = .uploading
            upload.updatedAt = .now
            try? modelContext.save()

            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            let task = session.uploadTask(with: request, fromFile: fileURL)
            task.taskDescription = upload.id.uuidString
            task.resume()
        } catch {
            markFailed(upload, message(for: error))
        }
    }

    private func commit(_ upload: MediaUpload) async {
        guard let photo = fetchPhoto(upload.photoID),
              let orgID = photo.project?.organization?.id,
              let objectKey = upload.objectKey else {
            markFailed(upload, "Missing commit context.")
            return
        }
        do {
            let body = CommitUploadBody(
                organizationId: orgID,
                photoId: photo.id,
                objectKey: objectKey,
                mediaType: photo.isVideo ? "video" : "photo",
                projectId: photo.project?.id
            )
            let _: CommitUploadDTO = try await api.send(.post("/media/commit", json: body))
            // Reflect server state immediately; sync pull later refines it.
            photo.processingStatus = .queued
            modelContext.delete(upload)
            try? modelContext.save()
        } catch {
            markFailed(upload, message(for: error))
        }
    }

    /// Called (on the main actor) after the background PUT task completes.
    private func finish(uploadID: UUID, httpStatus: Int?, errorMessage: String?) async {
        guard let upload = fetchUpload(uploadID), upload.state == .uploading else { return }
        if let errorMessage {
            markFailed(upload, errorMessage)
            return
        }
        guard let status = httpStatus, (200..<300).contains(status) else {
            markFailed(upload, "Upload failed (HTTP \(httpStatus ?? 0)).")
            return
        }
        upload.state = .committing
        upload.updatedAt = .now
        try? modelContext.save()
        await commit(upload)
    }

    // MARK: - Helpers

    private func markFailed(_ upload: MediaUpload, _ message: String) {
        upload.attempts += 1
        upload.state = .failed
        upload.lastError = message
        upload.updatedAt = .now
        try? modelContext.save()
    }

    private func fetchUpload(_ id: UUID) -> MediaUpload? {
        var descriptor = FetchDescriptor<MediaUpload>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchPhoto(_ id: UUID) -> Photo? {
        var descriptor = FetchDescriptor<Photo>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fileSize(_ url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return (attributes[.size] as? NSNumber)?.int64Value
    }

    private func contentType(ext: String, isVideo: Bool) -> String {
        if isVideo { return ext == "mp4" ? "video/mp4" : "video/quicktime" }
        switch ext {
        case "png": return "image/png"
        case "heic", "heif": return "image/heic"
        default: return "image/jpeg"
        }
    }

    private func message(for error: Error) -> String {
        (error as? APIError)?.userMessage ?? error.localizedDescription
    }
}

// MARK: - Background URLSession delegate

extension MediaUploader: URLSessionTaskDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let description = task.taskDescription, let id = UUID(uuidString: description) else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode
        let errorMessage = error?.localizedDescription
        Task { @MainActor in
            await self.finish(uploadID: id, httpStatus: status, errorMessage: errorMessage)
        }
    }

    /// The OS finished replaying background events after a relaunch/resume; call
    /// the completion handler the `AppDelegate` stashed so the app can suspend.
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            PushBridge.shared.backgroundCompletionHandler?()
            PushBridge.shared.backgroundCompletionHandler = nil
        }
    }
}
