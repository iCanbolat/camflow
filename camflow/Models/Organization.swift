import Foundation
import SwiftData

/// A company/organization tenant. Owns its own projects, member roster, and
/// branding (logo/name shown on report covers and photo watermarks). A user
/// can belong to several organizations and switch between them; the active one
/// is tracked by `Session`.
@Model
final class Organization {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Logo file inside `FileStorage.brandingDirectory`. Unique per org so logos
    /// don't collide across tenants.
    var logoFileName: String?
    var phone: String
    var email: String
    var website: String
    /// `Account.id` of the owner who created the organization.
    var ownerAccountID: UUID

    @Relationship(inverse: \OrgMember.organization)
    var members: [OrgMember] = []

    @Relationship(inverse: \Project.organization)
    var projects: [Project] = []

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(name: String, ownerAccountID: UUID) {
        self.id = UUID()
        self.name = name
        self.logoFileName = nil
        self.phone = ""
        self.email = ""
        self.website = ""
        self.ownerAccountID = ownerAccountID
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }
}

extension Organization {
    var activeMembers: [OrgMember] {
        members.filter { $0.deletedAt == nil }
    }
}
