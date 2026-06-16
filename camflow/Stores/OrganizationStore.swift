import Foundation
import SwiftData

/// Mutation layer for organizations + the current user's membership in them.
/// Replaces the old single-tenant `CompanyStore`.
@MainActor
struct OrganizationStore {
    let context: ModelContext

    /// The single organization `account` owns (created), if any. A user may join
    /// many orgs but owns at most one — this backs that guard.
    func ownedOrganization(for account: Account) -> Organization? {
        let accountID = account.id
        let descriptor = FetchDescriptor<Organization>(
            predicate: #Predicate { $0.ownerAccountID == accountID && $0.deletedAt == nil }
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// Creates an organization owned by `account` and inserts the owner's member
    /// row so the org shows up in the account's switcher immediately.
    /// A user owns at most one org: if `account` already owns one, that existing
    /// org is returned untouched rather than creating a duplicate.
    @discardableResult
    func create(name: String, owner account: Account) -> Organization {
        if let existing = ownedOrganization(for: account) { return existing }

        let org = Organization(name: name, ownerAccountID: account.id)
        context.insert(org)

        let ownerMember = OrgMember(
            name: account.displayName.isEmpty ? account.email : account.displayName,
            phoneNumber: "",
            title: String(localized: "Owner"),
            role: .owner,
            status: .active,
            colorHex: account.colorHex,
            accountID: account.id
        )
        context.insert(ownerMember)
        ownerMember.organization = org
        return org
    }

    func organization(id: UUID?) -> Organization? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<Organization>(
            predicate: #Predicate { $0.id == id && $0.deletedAt == nil }
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// Organizations the account belongs to, resolved from its member rows.
    func organizations(for account: Account) -> [Organization] {
        let accountID = account.id
        let descriptor = FetchDescriptor<OrgMember>(
            predicate: #Predicate { $0.accountID == accountID && $0.deletedAt == nil }
        )
        let members = (try? context.fetch(descriptor)) ?? []
        let orgs = members.compactMap { $0.organization }.filter { $0.deletedAt == nil }
        // De-dupe and present newest-first.
        var seen = Set<UUID>()
        return orgs
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func touch(_ org: Organization) {
        org.updatedAt = .now
        org.syncStatus = .local
    }

    func setPlan(_ tier: PlanTier, for org: Organization) {
        guard org.planTier != tier else { return }
        org.planTier = tier
        touch(org)
    }

    /// Mock subscription: set the chosen plan and stamp the subscription start
    /// (first time only), flipping the org out of trial/expired into `.active`.
    /// Real payment processing arrives with cloud accounts.
    func subscribe(_ tier: PlanTier, for org: Organization) {
        org.planTier = tier
        if org.subscriptionStartedAt == nil {
            org.subscriptionStartedAt = .now
        }
        touch(org)
    }

    /// Mock storage add-on purchase: stacks extra storage on the plan. Instant
    /// and free today; real billing arrives with cloud accounts.
    func setStorageAddOn(_ addOn: StorageAddOn, for org: Organization) {
        guard org.storageAddOn != addOn else { return }
        org.storageAddOn = addOn
        touch(org)
    }

    /// Children are left in place; `organizations(for:)` and `organization(id:)`
    /// filter `deletedAt == nil`, so the org disappears everywhere at once.
    func softDelete(_ org: Organization) {
        org.deletedAt = .now
        touch(org)
    }
}
