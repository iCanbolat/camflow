import Foundation
import SwiftData

/// Mutation layer for projects. Views read via @Query; all writes go through
/// here so a future sync engine can hook change tracking in one place.
@MainActor
struct ProjectStore {
    let context: ModelContext

    @discardableResult
    func create(
        name: String,
        address: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        label: ProjectLabel? = nil,
        organization: Organization? = nil
    ) -> Project {
        let project = Project(name: name, address: address, latitude: latitude, longitude: longitude, label: label)
        context.insert(project)
        project.organization = organization
        return project
    }

    func touch(_ project: Project) {
        project.updatedAt = .now
        project.syncStatus = .local
    }

    func softDelete(_ project: Project) {
        project.deletedAt = .now
        touch(project)
    }
}
