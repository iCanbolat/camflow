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
    // Stored as an optional raw string: lightweight migration leaves existing
    // rows NULL, and SwiftData crashes casting NULL into a non-optional enum.
    private var planTierRaw: String?

    var planTier: PlanTier {
        get { planTierRaw.flatMap(PlanTier.init(rawValue:)) ?? .basic }
        set { planTierRaw = newValue.rawValue }
    }

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
        self.planTierRaw = PlanTier.basic.rawValue
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

    var activeProjects: [Project] {
        projects.filter { $0.deletedAt == nil }
    }

    /// Plan limits gate creating new items only; existing data is never removed.
    var canAddProject: Bool {
        planTier.maxActiveProjects.map { activeProjects.count < $0 } ?? true
    }

    var canAddMember: Bool {
        planTier.maxMembers.map { activeMembers.count < $0 } ?? true
    }
}
