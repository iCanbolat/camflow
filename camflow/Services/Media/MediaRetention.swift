import Foundation
import SwiftData

/// 7-day on-device media retention. Frees space by deleting the **full-res local
/// bytes** of photos/videos that are safely in the cloud (`processingStatus ==
/// .done`), have no pending upload, and haven't been written/touched on disk in
/// 7 days. SwiftData rows and thumbnails stay, so grids stay fast and
/// `MediaProvider` re-downloads the full image on demand.
///
/// Gated on a live session — without the cloud backstop, purging would lose data.
@MainActor
final class MediaRetention {
    private let modelContext: ModelContext
    private let tokens: TokenStore

    nonisolated static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    private static let lastRunKey = "mediaPurgeLastRun"
    private static let runInterval: TimeInterval = 24 * 60 * 60

    init(context: ModelContext, tokens: TokenStore) {
        self.modelContext = context
        self.tokens = tokens
    }

    /// Runs the purge at most once per day.
    func purgeIfDue() async {
        let last = UserDefaults.standard.object(forKey: Self.lastRunKey) as? Date
        if let last, Date().timeIntervalSince(last) < Self.runInterval { return }
        await purge()
        UserDefaults.standard.set(Date(), forKey: Self.lastRunKey)
    }

    func purge() async {
        guard await tokens.hasSession else { return } // cloud is the re-download backstop

        let pending = Set(((try? modelContext.fetch(FetchDescriptor<MediaUpload>())) ?? []).map(\.photoID))
        let live = (try? modelContext.fetch(
            FetchDescriptor<Photo>(predicate: #Predicate { $0.deletedAt == nil })
        )) ?? []

        // Only purge fully-processed, not-pending photos; keep the thumbnail.
        let fileNames = live
            .filter { $0.processingStatus == .done && !pending.contains($0.id) && !$0.fileName.isEmpty }
            .map(\.fileName)
        guard !fileNames.isEmpty else { return }

        await Task.detached(priority: .utility) {
            MediaRetention.deleteStale(fileNames: fileNames)
        }.value
    }

    /// Deletes each named file in the photos directory whose on-disk modification
    /// date is older than `maxAge`. `nonisolated` so the file IO runs off-main.
    nonisolated static func deleteStale(fileNames: [String]) {
        let cutoff = Date().addingTimeInterval(-maxAge)
        let fileManager = FileManager.default
        for name in fileNames {
            let url = FileStorage.url(for: name, in: .photos)
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let modified = attributes[.modificationDate] as? Date,
                  modified < cutoff else { continue }
            try? fileManager.removeItem(at: url)
        }
    }
}
