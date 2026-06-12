import Foundation
import SwiftData

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var notes: String
    var coverPhotoID: UUID?

    var label: ProjectLabel?

    /// The organization that owns this project. The Home switcher scopes every
    /// project list to the active org via this relationship.
    var organization: Organization?

    @Relationship(deleteRule: .cascade, inverse: \Photo.project)
    var photos: [Photo] = []

    @Relationship(deleteRule: .cascade, inverse: \ProjectTask.project)
    var tasks: [ProjectTask] = []

    @Relationship(deleteRule: .cascade, inverse: \Checklist.project)
    var checklists: [Checklist] = []

    @Relationship(deleteRule: .cascade, inverse: \Report.project)
    var reports: [Report] = []

    @Relationship(deleteRule: .cascade, inverse: \BeforeAfterPair.project)
    var beforeAfterPairs: [BeforeAfterPair] = []

    @Relationship(deleteRule: .cascade, inverse: \Measurement.project)
    var measurements: [Measurement] = []

    @Relationship(inverse: \OrgMember.projects)
    var members: [OrgMember] = []

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(
        name: String,
        address: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        notes: String = "",
        label: ProjectLabel? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.notes = notes
        self.label = label
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }
}

extension Project {
    var activePhotos: [Photo] {
        photos.filter { $0.deletedAt == nil }
    }

    var hasCoordinate: Bool {
        latitude != nil && longitude != nil
    }

    var activeMembers: [OrgMember] {
        members.filter { $0.deletedAt == nil }
    }

    var activeMeasurements: [Measurement] {
        measurements.filter { $0.deletedAt == nil }
    }
}
