import Foundation

// Wire models for the cloud API. These are the JSON shapes the backend's DTO
// mappers (`api/src/common/mappers.ts`) emit and the request bodies its
// controllers accept. They are decoded/encoded with `JSONCoding`, whose custom
// ISO-8601 strategy parses the backend's `.toISOString()` timestamps (with
// fractional seconds) straight into `Date`. `CloudMappers` projects the response
// DTOs onto the SwiftData `@Model`s; nothing else should touch these directly.
//
// All `nonisolated` + `Sendable` so they cross the networking actors freely.

// MARK: - Response DTOs

nonisolated struct AccountDTO: Decodable, Sendable {
    let id: UUID
    let email: String
    let displayName: String
    let provider: String
    let colorHex: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

nonisolated struct OrganizationDTO: Decodable, Sendable {
    let id: UUID
    let name: String
    let logoFileName: String?
    let phone: String
    let email: String
    let website: String
    let ownerAccountId: UUID
    let planTier: String
    let storageAddOn: String
    let trialStartedAt: Date?
    let subscriptionStartedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    // Derived entitlement fields (subscriptionStatus/effectivePlan/…) are sent
    // by the backend but recomputed on-device, so they are intentionally not
    // decoded here.
}

nonisolated struct MemberDTO: Decodable, Sendable {
    let id: UUID
    let organizationId: UUID
    let accountId: UUID?
    let name: String
    let phoneNumber: String
    let title: String
    let role: String
    let status: String
    let colorHex: String
    let inviteCode: String?
    let inviteCreatedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

/// `/auth/*` success payload: the account plus a fresh token pair.
nonisolated struct SessionResponseDTO: Decodable, Sendable {
    let account: AccountDTO
    let accessToken: String
    let accessTokenExpiresIn: Int
    let refreshToken: String
    let refreshTokenExpiresAt: Date
}

/// `GET /invites/:code` — what the invitee sees before accepting.
nonisolated struct InvitePreviewDTO: Decodable, Sendable {
    let organizationName: String
    let organizationLogoFileName: String?
    let memberName: String
    let roleDisplayName: String
}

/// `POST /organizations/:orgId/members/:memberId/invite` — the issued link.
nonisolated struct InviteLinkDTO: Decodable, Sendable {
    let code: String
    let universalUrl: String
    let customSchemeUrl: String
}

// MARK: - Request bodies

nonisolated struct SignUpBody: Encodable, Sendable {
    let email: String
    let password: String
    let displayName: String
}

nonisolated struct SignInBody: Encodable, Sendable {
    let email: String
    let password: String
}

nonisolated struct AppleSignInBody: Encodable, Sendable {
    let identityToken: String
    let displayName: String?
}

nonisolated struct GoogleSignInBody: Encodable, Sendable {
    let idToken: String
}

nonisolated struct RefreshBody: Encodable, Sendable {
    let refreshToken: String
}

nonisolated struct CreateOrganizationBody: Encodable, Sendable {
    /// Client UUID so an org keeps its id between the device and the server.
    let id: UUID
    let name: String
    let phone: String?
    let email: String?
    let website: String?
}

nonisolated struct InviteMemberBody: Encodable, Sendable {
    /// Client UUID so the member row keeps its id across the device/server.
    let id: UUID
    let name: String
    let phoneNumber: String?
    let title: String?
    let role: String?
    let projectIds: [UUID]?
}
