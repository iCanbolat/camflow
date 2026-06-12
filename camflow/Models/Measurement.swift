import Foundation
import SwiftData
import simd

/// One AR point-to-point measuring session: an ordered list of segments with
/// world-space endpoints, plus a link to the snapshot photo saved alongside.
@Model
final class Measurement {
    enum Unit: String, Codable {
        case meters
        case feet
    }

    @Attribute(.unique) var id: UUID
    var capturedAt: Date
    /// Display unit chosen while measuring; distances are stored in meters.
    var unit: Unit
    /// JSON-encoded `[MeasurementSegment]` — same pattern as `Photo.annotationData`.
    var segmentsData: Data
    var totalMeters: Double
    /// UUID link to the snapshot Photo (same convention as `Report.photoIDs`).
    var snapshotPhotoID: UUID?
    var notes: String

    var project: Project?

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(
        segments: [MeasurementSegment],
        unit: Unit,
        snapshotPhotoID: UUID? = nil,
        notes: String = "",
        project: Project? = nil
    ) {
        self.id = UUID()
        self.capturedAt = .now
        self.unit = unit
        self.segmentsData = (try? JSONEncoder().encode(segments)) ?? Data()
        self.totalMeters = segments.reduce(0) { $0 + $1.distanceMeters }
        self.snapshotPhotoID = snapshotPhotoID
        self.notes = notes
        self.project = project
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }
}

extension Measurement {
    var segments: [MeasurementSegment] {
        (try? JSONDecoder().decode([MeasurementSegment].self, from: segmentsData)) ?? []
    }

    /// "2.45 m" / "8.0 ft" — distances are always stored in meters.
    static func format(meters: Double, in unit: Unit) -> String {
        switch unit {
        case .meters: String(format: "%.2f m", meters)
        case .feet: String(format: "%.1f ft", meters * 3.28084)
        }
    }
}

/// A single measured span in ARKit world coordinates.
struct MeasurementSegment: Codable {
    var start: SIMD3<Float>
    var end: SIMD3<Float>
    var distanceMeters: Double

    init(start: SIMD3<Float>, end: SIMD3<Float>) {
        self.start = start
        self.end = end
        self.distanceMeters = Double(simd_distance(start, end))
    }
}
