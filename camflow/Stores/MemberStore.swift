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
        projects: [Project],
        organization: Organization?
    ) -> OrgMember {
        let colorHex = TagPalette.colors[abs(name.hashValue) % TagPalette.colors.count]
        let member = OrgMember(
            name: name,
            phoneNumber: phoneNumber,
            title: title,
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

    func softDelete(_ member: OrgMember) {
        guard member.role != .owner else { return }
        member.deletedAt = .now
        member.projects.removeAll()
        touch(member)
    }
}
