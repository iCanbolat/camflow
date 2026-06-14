import Foundation
import UIKit

/// Owns the on-disk layout. SwiftData stores only file names; bytes live here.
/// nonisolated: file IO is called from background tasks during photo processing.
nonisolated enum FileStorage {
    enum Directory: String {
        case photos = "Photos"
        case branding = "Branding"
        case reports = "Reports"
        case pages = "Pages"

        var url: URL {
            let base: URL
            switch self {
            case .photos, .branding:
                base = URL.applicationSupportDirectory
            case .reports, .pages:
                base = URL.documentsDirectory
            }
            let url = base.appending(path: rawValue, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }

    static func url(for fileName: String, in directory: Directory) -> URL {
        directory.url.appending(path: fileName)
    }

    @discardableResult
    static func save(_ data: Data, named fileName: String, in directory: Directory) throws -> URL {
        let url = url(for: fileName, in: directory)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Moves an already-written file (e.g. a finished movie recording) into the
    /// store without loading its bytes into memory.
    @discardableResult
    static func adopt(fileAt sourceURL: URL, named fileName: String, in directory: Directory) throws -> URL {
        let destination = url(for: fileName, in: directory)
        try FileManager.default.moveItem(at: sourceURL, to: destination)
        return destination
    }

    static func load(_ fileName: String, in directory: Directory) -> Data? {
        try? Data(contentsOf: url(for: fileName, in: directory))
    }

    static func loadImage(_ fileName: String, in directory: Directory) -> UIImage? {
        load(fileName, in: directory).flatMap(UIImage.init(data:))
    }

    static func delete(_ fileName: String, in directory: Directory) {
        try? FileManager.default.removeItem(at: url(for: fileName, in: directory))
    }

    /// Total bytes used by a directory — surfaced in Settings → Storage.
    static func totalSize(of directory: Directory) -> Int64 {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory.url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return files.reduce(0) { total, file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }
}
