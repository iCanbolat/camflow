import Foundation
import SwiftData

/// Projects server response DTOs onto the local SwiftData `@Model`s. Every
/// upsert is keyed by the shared `id`, marks the row `.synced`, and keeps the
/// server's `updatedAt` (no `touch()` — these writes are not local mutations).
///
/// Phase 1 only needs accounts, organizations, and members; Phase 2's sync
/// engine generalizes this into a per-entity mapper registry.
@MainActor
enum CloudMappers {
    @discardableResult
    static func upsertAccount(_ dto: AccountDTO, in context: ModelContext) -> Account {
        let account = existing(Account.self, id: dto.id, in: context)
            ?? insert(Account(email: dto.email,
                              displayName: dto.displayName,
                              provider: provider(dto.provider),
                              colorHex: dto.colorHex),
                     in: context)
        account.id = dto.id
        account.email = dto.email
        account.displayName = dto.displayName
        account.provider = provider(dto.provider)
        account.colorHex = dto.colorHex
        // Cloud owns credentials; the local password hash is never populated.
        account.passwordHash = nil
        apply(timestamps: dto.createdAt, dto.updatedAt, dto.deletedAt, to: account)
        return account
    }

    @discardableResult
    static func upsertOrganization(_ dto: OrganizationDTO, in context: ModelContext) -> Organization {
        let org = existing(Organization.self, id: dto.id, in: context)
            ?? insert(Organization(name: dto.name, ownerAccountID: dto.ownerAccountId), in: context)
        org.id = dto.id
        org.name = dto.name
        org.logoFileName = dto.logoFileName
        org.phone = dto.phone
        org.email = dto.email
        org.website = dto.website
        org.ownerAccountID = dto.ownerAccountId
        org.planTier = PlanTier(rawValue: dto.planTier) ?? .basic
        org.storageAddOn = StorageAddOn(rawValue: dto.storageAddOn) ?? .none
        org.trialStartedAt = dto.trialStartedAt
        org.subscriptionStartedAt = dto.subscriptionStartedAt
        apply(timestamps: dto.createdAt, dto.updatedAt, dto.deletedAt, to: org)
        return org
    }

    @discardableResult
    static func upsertMember(_ dto: MemberDTO, in context: ModelContext) -> OrgMember {
        let member = existing(OrgMember.self, id: dto.id, in: context)
            ?? insert(OrgMember(name: dto.name, phoneNumber: dto.phoneNumber), in: context)
        member.id = dto.id
        member.name = dto.name
        member.phoneNumber = dto.phoneNumber
        member.title = dto.title
        member.role = OrgMember.Role(rawValue: dto.role) ?? .standard
        member.status = OrgMember.Status(rawValue: dto.status) ?? .invited
        member.colorHex = dto.colorHex
        member.accountID = dto.accountId
        member.inviteCode = dto.inviteCode
        member.inviteCreatedAt = dto.inviteCreatedAt
        member.organization = organization(id: dto.organizationId, in: context)
        apply(timestamps: dto.createdAt, dto.updatedAt, dto.deletedAt, to: member)
        return member
    }

    // MARK: - Helpers

    static func organization(id: UUID, in context: ModelContext) -> Organization? {
        existing(Organization.self, id: id, in: context)
    }

    private static func provider(_ raw: String) -> Account.Provider {
        Account.Provider(rawValue: raw) ?? .email
    }

    /// Finds a row by id regardless of tombstone state, so a server delete can
    /// update a previously-live row (and vice versa).
    private static func existing<T: PersistentModel>(
        _ type: T.Type,
        id: UUID,
        in context: ModelContext
    ) -> T? where T: CloudIdentifiable {
        var descriptor = FetchDescriptor<T>(predicate: T.predicate(id: id))
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func insert<T: PersistentModel>(_ model: T, in context: ModelContext) -> T {
        context.insert(model)
        return model
    }
}

/// Lets `CloudMappers.existing` fetch any cloud-backed model by its shared id.
/// (`#Predicate` can't be written generically over `\.id`, so each model
/// supplies its own.)
protocol CloudIdentifiable {
    static func predicate(id: UUID) -> Predicate<Self>
}

extension Account: CloudIdentifiable {
    static func predicate(id: UUID) -> Predicate<Account> {
        #Predicate { $0.id == id }
    }
}

extension Organization: CloudIdentifiable {
    static func predicate(id: UUID) -> Predicate<Organization> {
        #Predicate { $0.id == id }
    }
}

extension OrgMember: CloudIdentifiable {
    static func predicate(id: UUID) -> Predicate<OrgMember> {
        #Predicate { $0.id == id }
    }
}

// MARK: - Timestamp application

private protocol CloudTimestamped: AnyObject {
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    var syncStatus: SyncStatus { get set }
}

extension Account: CloudTimestamped {}
extension Organization: CloudTimestamped {}
extension OrgMember: CloudTimestamped {}

private extension CloudMappers {
    static func apply(timestamps created: Date, _ updated: Date, _ deleted: Date?, to model: any CloudTimestamped) {
        model.createdAt = created
        model.updatedAt = updated
        model.deletedAt = deleted
        model.syncStatus = .synced
    }
}
