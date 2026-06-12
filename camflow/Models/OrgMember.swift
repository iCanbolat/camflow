import Foundation
import SwiftData

/// A person in the organization. Members are invited by phone number and
/// scoped to the projects they're added to. In the local-first v1 the invite
/// stays `.invited`; the cloud sync phase delivers the SMS invite + login and
/// flips members to `.active`.
@Model
final class OrgMember {
    enum Role: String, Codable {
        case owner
        case member
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
        role: Role = .member,
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
