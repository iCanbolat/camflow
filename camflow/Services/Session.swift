import Foundation
import SwiftData
import Observation

/// Single source of truth for "who is signed in" and "which organization is
/// active". Injected at the app root via `.environment(session)`. Org-scoped
/// views read `activeOrganizationID` to filter their queries; switching orgs
/// mutates this object, which (being `@Observable`) refreshes those views.
@MainActor
@Observable
final class Session {
    private let context: ModelContext

    private(set) var currentAccount: Account?
    private(set) var activeOrganizationID: UUID?
    /// Invite code from a tapped link or manual entry, waiting to be redeemed.
    /// Persisted so it survives the welcome → auth journey (and app restarts);
    /// deliberately NOT cleared on sign-out so a same-device invitee can sign
    /// up and still land on the join screen.
    private(set) var pendingInviteCode: String?

    private enum Keys {
        static let account = "currentAccountID"
        static let org = "activeOrganizationID"
        static let pendingInvite = "pendingInviteCode"
        /// Mirrors `RootCoordinatorView`'s @AppStorage gate.
        static let hasSeenWelcome = "hasSeenWelcome"
    }

    init(context: ModelContext) {
        self.context = context

        if let raw = UserDefaults.standard.string(forKey: Keys.account),
           let id = UUID(uuidString: raw) {
            currentAccount = Self.account(id: id, context: context)
        }
        if let raw = UserDefaults.standard.string(forKey: Keys.org),
           let id = UUID(uuidString: raw) {
            activeOrganizationID = id
        }
        pendingInviteCode = UserDefaults.standard.string(forKey: Keys.pendingInvite)
        normalizeActiveOrg()
    }

    // MARK: - Derived state

    var organizations: [Organization] {
        guard let account = currentAccount else { return [] }
        return OrganizationStore(context: context).organizations(for: account)
    }

    /// The org the current account owns (created), if any. A user owns at most
    /// one org but may join others, so this is distinct from `organizations`.
    var ownedOrganization: Organization? {
        guard let account = currentAccount else { return nil }
        return OrganizationStore(context: context).ownedOrganization(for: account)
    }

    /// Whether the current account already owns an organization. Gates the
    /// "Create Organization" entry point so a user can't own a second one.
    var ownsOrganization: Bool { ownedOrganization != nil }

    var activeOrganization: Organization? {
        OrganizationStore(context: context).organization(id: activeOrganizationID)
    }

    /// The current account's member row in the active organization.
    var activeMembership: OrgMember? {
        guard let accountID = currentAccount?.id, let orgID = activeOrganizationID else { return nil }
        let descriptor = FetchDescriptor<OrgMember>(
            predicate: #Predicate { $0.accountID == accountID && $0.deletedAt == nil }
        )
        let members = (try? context.fetch(descriptor)) ?? []
        return members.first { $0.organization?.id == orgID }
    }

    /// Role in the active org. The member row wins; the `ownerAccountID`
    /// fallback covers orgs created before owner member rows existed.
    /// Note: `can(_:)` re-evaluates on account/org switches; editing the
    /// current user's *own* member row in-place won't re-render gated views,
    /// which is acceptable while the only signed-in account is local.
    var activeRole: OrgMember.Role {
        if let membership = activeMembership { return membership.role }
        if let account = currentAccount, account.id == activeOrganization?.ownerAccountID {
            return .owner
        }
        return .standard
    }

    func can(_ permission: Permission) -> Bool {
        activeRole.can(permission)
    }

    var activePlan: PlanTier {
        activeOrganization?.planTier ?? .basic
    }

    // MARK: - Mutations

    func signIn(_ account: Account) {
        currentAccount = account
        UserDefaults.standard.set(account.id.uuidString, forKey: Keys.account)
        normalizeActiveOrg()
    }

    func setActiveOrg(_ org: Organization) {
        activeOrganizationID = org.id
        UserDefaults.standard.set(org.id.uuidString, forKey: Keys.org)
    }

    func switchTo(_ org: Organization) {
        setActiveOrg(org)
    }

    func setPendingInvite(code: String?) {
        pendingInviteCode = code
        if let code {
            UserDefaults.standard.set(code, forKey: Keys.pendingInvite)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.pendingInvite)
        }
    }

    func signOut() {
        currentAccount = nil
        activeOrganizationID = nil
        UserDefaults.standard.removeObject(forKey: Keys.account)
        UserDefaults.standard.removeObject(forKey: Keys.org)
        // Signing out restarts the journey from the welcome slides, not AuthView.
        UserDefaults.standard.set(false, forKey: Keys.hasSeenWelcome)
    }

    /// Called after the active organization is soft-deleted: falls back to the
    /// next remaining org, or to nil so the root coordinator shows org creation.
    func handleOrgDeleted() {
        activeOrganizationID = nil
        UserDefaults.standard.removeObject(forKey: Keys.org)
        normalizeActiveOrg()
    }

    /// Ensures the active org is one the current account actually belongs to,
    /// falling back to the first available org (or nil).
    private func normalizeActiveOrg() {
        let orgs = organizations
        if let id = activeOrganizationID, orgs.contains(where: { $0.id == id }) {
            return
        }
        if let first = orgs.first {
            setActiveOrg(first)
        } else {
            activeOrganizationID = nil
            UserDefaults.standard.removeObject(forKey: Keys.org)
        }
    }

    private static func account(id: UUID, context: ModelContext) -> Account? {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == id && $0.deletedAt == nil }
        )
        return (try? context.fetch(descriptor))?.first
    }
}
