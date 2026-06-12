import AVFoundation
import UIKit

/// CPU-bound video work (thumbnails, duration probing), safe off the main actor.
nonisolated enum VideoProcessor {
    /// First-frame JPEG used for grids and strips, matching ImageProcessor output.
    static func makeThumbnail(forVideoAt url: URL, maxPixelSize: CGFloat = 600) async -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        // Without the transform, portrait clips come back rotated.
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        guard let cgImage = try? await generator.image(at: .zero).image else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
    }

    static func duration(of url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        return duration.seconds
    }
}
