import Foundation
import SwiftData

/// Mutation layer for organizations + the current user's membership in them.
/// Replaces the old single-tenant `CompanyStore`.
@MainActor
struct OrganizationStore {
    let context: ModelContext

    /// Creates an organization owned by `account` and inserts the owner's member
    /// row so the org shows up in the account's switcher immediately.
    @discardableResult
    func create(name: String, owner account: Account) -> Organization {
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
}
