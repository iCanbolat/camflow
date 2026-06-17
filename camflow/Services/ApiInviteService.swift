import Foundation
import SwiftData

/// Cloud `InviteService`: code issuance, preview, and redemption live on the
/// backend (`/invites/*`, `/organizations/:org/members/:id/invite`). Backend
/// error codes map onto the existing `InviteError` cases so the UI is unchanged.
@MainActor
struct ApiInviteService: InviteService {
    let api: APIClient
    let context: ModelContext

    func issueInvite(for member: OrgMember) async throws -> InviteLink {
        guard let orgID = member.organization?.id else {
            throw InviteError.organizationUnavailable
        }
        let memberID = member.id
        do {
            let dto: InviteLinkDTO = try await api.send(
                .post("/organizations/\(orgID)/members/\(memberID)/invite")
            )
            // Mirror the issued code locally so the row matches the server.
            member.inviteCode = dto.code
            if member.inviteCreatedAt == nil { member.inviteCreatedAt = .now }
            try? context.save()
            return try Self.link(from: dto)
        } catch let error as APIError {
            throw Self.mapped(error)
        }
    }

    func preview(code: String) async throws -> InvitePreview {
        do {
            let dto: InvitePreviewDTO = try await api.send(
                .get("/invites/\(code)", requiresAuth: false)
            )
            return InvitePreview(
                organizationName: dto.organizationName,
                organizationLogoFileName: dto.organizationLogoFileName,
                memberName: dto.memberName,
                roleDisplayName: dto.roleDisplayName
            )
        } catch let error as APIError {
            throw Self.mapped(error)
        }
    }

    func redeem(code: String, account: Account) async throws -> Organization {
        do {
            let dto: OrganizationDTO = try await api.send(.post("/invites/\(code)/redeem"))
            let org = CloudMappers.upsertOrganization(dto, in: context)
            try? context.save()
            // Pull the roster so the redeemer's own member row lands locally and
            // `Session.activeMembership` resolves once the org becomes active.
            await pullMembers(orgID: org.id)
            return org
        } catch let error as APIError {
            throw Self.mapped(error)
        }
    }

    // MARK: - Internals

    private func pullMembers(orgID: UUID) async {
        guard let members: [MemberDTO] = try? await api.send(
            .get("/organizations/\(orgID)/members")
        ) else { return }
        for dto in members { CloudMappers.upsertMember(dto, in: context) }
        try? context.save()
    }

    private static func link(from dto: InviteLinkDTO) throws -> InviteLink {
        guard let universal = URL(string: dto.universalUrl),
              let custom = URL(string: dto.customSchemeUrl) else {
            throw InviteError.codeNotFound
        }
        return InviteLink(code: dto.code, universalURL: universal, customSchemeURL: custom)
    }

    private static func mapped(_ error: APIError) -> Error {
        switch error.code {
        case "codeNotFound": return InviteError.codeNotFound
        case "organizationUnavailable": return InviteError.organizationUnavailable
        case "alreadyRedeemed": return InviteError.alreadyRedeemed
        case "alreadyMember":
            if case let .server(server) = error,
               let raw = server.organizationId, let id = UUID(uuidString: raw) {
                return InviteError.alreadyMember(
                    organizationID: id,
                    organizationName: server.organizationName ?? ""
                )
            }
            return InviteError.codeNotFound
        default:
            return error
        }
    }
}
