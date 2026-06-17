import Foundation
import SwiftData

/// Creates org members on the backend so the host-side invite flow is cloud-true
/// in Phase 1: a member you invite exists server-side immediately, which is what
/// `ApiInviteService.issueInvite` needs. Member *edits* and deletes still flow
/// through the local stores and will be pushed by Phase 2's sync engine.
@MainActor
struct ApiMemberService {
    let api: APIClient
    let context: ModelContext

    /// Invites a person into `organization` (status `invited`), returning the
    /// upserted local member. The client-generated id is sent so the row keeps
    /// the same identity once Phase 2 pull/push takes over.
    @discardableResult
    func create(
        in organization: Organization,
        name: String,
        phoneNumber: String,
        title: String,
        role: OrgMember.Role,
        projects: [Project]
    ) async throws -> OrgMember {
        // The owner role is never assignable via invite (mirrors MemberStore).
        let safeRole: OrgMember.Role = role == .owner ? .standard : role
        let body = InviteMemberBody(
            id: UUID(),
            name: name,
            phoneNumber: phoneNumber,
            title: title,
            role: safeRole.rawValue,
            projectIds: projects.isEmpty ? nil : projects.map(\.id)
        )
        let dto: MemberDTO = try await api.send(
            .post("/organizations/\(organization.id)/members", json: body)
        )
        let member = CloudMappers.upsertMember(dto, in: context)
        // The roster DTO doesn't carry project associations; set them locally.
        member.projects = projects
        try? context.save()
        return member
    }
}
