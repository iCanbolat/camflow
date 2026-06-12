import Foundation
import SwiftData

/// Mutation layer for AR measurements.
@MainActor
struct MeasurementStore {
    let context: ModelContext

    @discardableResult
    func create(
        segments: [MeasurementSegment],
        unit: Measurement.Unit,
        snapshotPhotoID: UUID?,
        project: Project?
    ) -> Measurement {
        let measurement = Measurement(
            segments: segments,
            unit: unit,
            snapshotPhotoID: snapshotPhotoID,
            project: project
        )
        context.insert(measurement)
        project?.updatedAt = .now
        return measurement
    }

    func touch(_ measurement: Measurement) {
        measurement.updatedAt = .now
        measurement.syncStatus = .local
    }

    func softDelete(_ measurement: Measurement) {
        measurement.deletedAt = .now
        touch(measurement)
    }
}
