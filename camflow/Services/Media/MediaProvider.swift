import Foundation
import UIKit

/// Resolves media for display: **local file first**, else fetch a signed CDN URL
/// (`GET /media/:id/urls`), download the variant, cache it on disk under the
/// photo's local file name (so the rest of the app's local-file lookups hit) and
/// in an in-memory `NSCache`. An `actor` so the cache + in-flight dedupe are
/// concurrency-safe and decoding/network stay off the main actor.
actor MediaProvider {
    enum Variant: Sendable {
        case thumbnail
        case full
    }

    /// The minimal, `Sendable` view of a `Photo` the provider needs — built on the
    /// main actor by the view so no `@Model` crosses the actor boundary.
    nonisolated struct Ref: Sendable {
        let photoID: UUID
        let organizationID: UUID?
        let fileName: String
        let thumbnailFileName: String
        let isVideo: Bool

        @MainActor
        init(_ photo: Photo, organizationID: UUID?) {
            self.photoID = photo.id
            self.organizationID = photo.project?.organization?.id ?? organizationID
            self.fileName = photo.fileName
            self.thumbnailFileName = photo.thumbnailFileName
            self.isVideo = photo.isVideo
        }
    }

    private let api: APIClient
    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init(api: APIClient) {
        self.api = api
        cache.countLimit = 200
    }

    /// A display image for `ref`. Thumbnails are downsampled to bound memory.
    func image(for ref: Ref, variant: Variant) async -> UIImage? {
        guard !ref.isVideo || variant == .thumbnail else { return nil } // videos play via `playbackURL`
        let fileName = variant == .thumbnail ? ref.thumbnailFileName : ref.fileName
        guard !fileName.isEmpty else { return nil }

        if let cached = cache.object(forKey: fileName as NSString) { return cached }
        if let running = inFlight[fileName] { return await running.value }

        let task = Task<UIImage?, Never> { [api] in
            await Self.load(fileName: fileName, ref: ref, variant: variant, api: api)
        }
        inFlight[fileName] = task
        let image = await task.value
        inFlight[fileName] = nil
        if let image { cache.setObject(image, forKey: fileName as NSString) }
        return image
    }

    /// A URL AVPlayer can play: the local file if present, else the processed
    /// (streamable) signed URL.
    func playbackURL(for ref: Ref) async -> URL? {
        let localURL = FileStorage.url(for: ref.fileName, in: .photos)
        if FileManager.default.fileExists(atPath: localURL.path) { return localURL }
        guard let dto = await urls(for: ref), let processed = dto.processed else { return nil }
        return URL(string: processed)
    }

    // MARK: - Loading

    private static func load(fileName: String, ref: Ref, variant: Variant, api: APIClient) async -> UIImage? {
        // Local-bytes-first.
        if let data = FileStorage.load(fileName, in: .photos) {
            return decode(data, variant: variant)
        }
        // Remote: signed URL → download → cache to disk under the local name.
        guard let dto = await urls(for: ref, api: api) else { return nil }
        let remote = variant == .thumbnail
            ? (dto.thumbnail ?? dto.processed)
            : (dto.processed ?? dto.watermarked ?? dto.thumbnail)
        guard let remote, let url = URL(string: remote) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else {
            return nil
        }
        _ = try? FileStorage.save(data, named: fileName, in: .photos)
        return decode(data, variant: variant)
    }

    private static func decode(_ data: Data, variant: Variant) -> UIImage? {
        switch variant {
        case .thumbnail:
            // Bound memory: downsample large originals to a grid-sized thumbnail.
            return ImageProcessor.makeThumbnail(from: data, maxPixelSize: 600)
                .flatMap(UIImage.init(data:)) ?? UIImage(data: data)
        case .full:
            return UIImage(data: data)
        }
    }

    private func urls(for ref: Ref) async -> MediaURLsDTO? {
        await Self.urls(for: ref, api: api)
    }

    private static func urls(for ref: Ref, api: APIClient) async -> MediaURLsDTO? {
        guard let orgID = ref.organizationID else { return nil }
        let query = [URLQueryItem(name: "organizationId", value: orgID.uuidString)]
        return try? await api.send(.get("/media/\(ref.photoID.uuidString)/urls", query: query))
    }
}
