import Foundation
import SwiftData

@MainActor
struct MemberStore {
    let context: ModelContext

    @discardableResult
    func invite(
        name: String,
        phoneNumber: String,
        title: String,
        role: OrgMember.Role = .standard,
        projects: [Project],
        organization: Organization?
    ) -> OrgMember {
        let colorHex = TagPalette.colors[abs(name.hashValue) % TagPalette.colors.count]
        let member = OrgMember(
            name: name,
            phoneNumber: phoneNumber,
            title: title,
            role: role == .owner ? .standard : role,
            colorHex: colorHex
        )
        context.insert(member)
        member.organization = organization
        member.projects = projects
        return member
    }

    func touch(_ member: OrgMember) {
        member.updatedAt = .now
        member.syncStatus = .local
    }

    func assignInviteCode(_ code: String, to member: OrgMember) {
        member.inviteCode = code
        member.inviteCreatedAt = .now
        touch(member)
    }

    /// Links a signed-in account to an invited member row and activates it.
    func activate(_ member: OrgMember, accountID: UUID) {
        member.accountID = accountID
        member.status = .active
        touch(member)
    }

    /// The owner role is never reassigned: not granted, not taken away.
    func setRole(_ role: OrgMember.Role, for member: OrgMember) {
        guard member.role != .owner, role != .owner, member.role != role else { return }
        member.role = role
        touch(member)
    }

    func softDelete(_ member: OrgMember) {
        guard member.role != .owner else { return }
        member.deletedAt = .now
        member.projects.removeAll()
        touch(member)
    }
}
