import Foundation
import SwiftData

/// A person in the organization. Members are invited with a shareable link
/// (`https://camflow.app/invite/<code>`); everyone sees all of the
/// organization's projects, and project assignment drives task assignment and
/// (future) notifications. In the local-first v1 redemption happens on-device
/// via `LocalInviteService`; the cloud phase moves code issuance/redemption to
/// the backend and flips members to `.active` when they join.
@Model
final class OrgMember {
    enum Role: String, Codable, CaseIterable {
        case owner
        case admin
        case manager
        // Raw value stays "member" so rows written before the role system
        // decode without migration.
        case standard = "member"
    }

    enum Status: String, Codable {
        case invited
        case active
    }

    @Attribute(.unique) var id: UUID
    var name: String
    var phoneNumber: String
    /// Job title shown across the app, e.g. "Site Foreman".
    var title: String
    var role: Role
    var status: Status
    /// Avatar color.
    var colorHex: String

    /// The organization this member belongs to.
    var organization: Organization?
    /// `Account.id` when this member row is an app user (the current user in
    /// each org they belong to). `nil` for people invited by phone who haven't
    /// signed up yet. "Orgs I belong to" = members where `accountID == my id`.
    var accountID: UUID?

    /// Short shareable invite code embedded in the invite link. Optional so
    /// existing rows migrate as NULL; issued lazily by `InviteService`.
    /// Uniqueness is enforced at generation time, not with a constraint —
    /// adding `.unique` to a migrated column is risky.
    var inviteCode: String?
    var inviteCreatedAt: Date?

    /// Projects this member can see and contribute to.
    var projects: [Project] = []

    @Relationship(inverse: \ProjectTask.assignee)
    var assignedTasks: [ProjectTask] = []

    @Relationship(inverse: \Checklist.assignee)
    var assignedChecklists: [Checklist] = []

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(
        name: String,
        phoneNumber: String,
        title: String = "",
        role: Role = .standard,
        status: Status = .invited,
        colorHex: String = TagPalette.colors[3],
        accountID: UUID? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.phoneNumber = phoneNumber
        self.title = title
        self.role = role
        self.status = status
        self.colorHex = colorHex
        self.accountID = accountID
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }
}

extension OrgMember.Role {
    /// Roles that can be assigned in pickers. `.owner` is never assignable:
    /// there is exactly one owner per organization (its creator).
    static let assignable: [OrgMember.Role] = [.admin, .manager, .standard]

    var displayName: String {
        switch self {
        case .owner: String(localized: "Owner")
        case .admin: String(localized: "Admin")
        case .manager: String(localized: "Manager")
        case .standard: String(localized: "Standard")
        }
    }

    var chipColorHex: String {
        switch self {
        case .owner: "#FF6B35"
        case .admin: "#E0475B"
        case .manager: "#1B98E0"
        case .standard: "#13B5B1"
        }
    }

    /// One-line description shown under role pickers.
    var summary: String {
        switch self {
        case .owner:
            String(localized: "Full control, including deleting the organization.")
        case .admin:
            String(localized: "Everything: billing, company profile, team and roles.")
        case .manager:
            String(localized: "Manages the team, tags, labels, templates, and projects.")
        case .standard:
            String(localized: "Works in assigned projects only: adds photos and completes tasks and checklists assigned to them.")
        }
    }
}

extension OrgMember {
    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var activeProjects: [Project] {
        projects.filter { $0.deletedAt == nil }
    }
}
