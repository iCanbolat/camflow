import Foundation
import ImageIO
import CoreLocation
import UniformTypeIdentifiers

/// CPU-bound image work, safe to run off the main actor.
nonisolated enum ImageProcessor {
    /// Downscaled JPEG used for grids and strips.
    static func makeThumbnail(from data: Data, maxPixelSize: Int = 600) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    struct ImportedMetadata {
        var capturedAt: Date?
        var latitude: Double?
        var longitude: Double?
    }

    /// Reads capture date and GPS from EXIF for photos imported from the library.
    static func metadata(from data: Data) -> ImportedMetadata {
        var result = ImportedMetadata()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return result
        }

        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            formatter.timeZone = .current
            result.capturedAt = formatter.date(from: dateString)
        }

        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
           let longitude = gps[kCGImagePropertyGPSLongitude] as? Double {
            let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
            result.latitude = latRef == "S" ? -latitude : latitude
            result.longitude = lonRef == "W" ? -longitude : longitude
        }

        return result
    }
}
