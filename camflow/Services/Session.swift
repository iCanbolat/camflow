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

    /// Bumped when a plan/subscription mutation is routed through this session,
    /// so views observing `Session` (e.g. the root paywall gate) re-evaluate
    /// entitlement even though the change lives on the SwiftData `Organization`.
    private(set) var revision = 0

    /// Bumped when a notification deep link (push tap) asks to open the
    /// notifications surface. `RootTabView` switches to Home and `HomeView`
    /// presents the sheet; a counter avoids any reset coordination.
    private(set) var notificationsRequest = 0

    /// Routes a notification deep-link tap to the notifications screen.
    func requestNotifications() {
        notificationsRequest += 1
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

    /// Whether the current user may act on this task (complete it, comment,
    /// attach photos). Privileged roles (`.manageTasks`) may act on anything;
    /// standard members only on tasks assigned to them. Structural changes
    /// (create/edit/delete/reassign) are gated separately by `.manageTasks`.
    func canModify(_ task: ProjectTask) -> Bool {
        if can(.manageTasks) { return true }
        guard let me = activeMembership?.id, let assignee = task.assignee?.id else { return false }
        return me == assignee
    }

    /// Whether the current user may act on this checklist (check items off,
    /// attach proof photos). Same rule as `canModify(_ task:)`.
    func canModify(_ checklist: Checklist) -> Bool {
        if can(.manageTasks) { return true }
        guard let me = activeMembership?.id, let assignee = checklist.assignee?.id else { return false }
        return me == assignee
    }

    /// Entitlement for all feature gates — the active org's `effectivePlan`
    /// (Premium during the trial, the subscribed tier after). Touches `revision`
    /// so a subscription change routed through `subscribe(_:)` re-renders gates.
    var activePlan: PlanTier {
        _ = revision
        return activeOrganization?.effectivePlan ?? .basic
    }

    /// True only when the current account *created* the active org (vs. was
    /// invited to it). The trial & paywall are scoped to owned orgs.
    var activeOrgIsOwned: Bool {
        guard let accountID = currentAccount?.id, let org = activeOrganization else { return false }
        return org.ownerAccountID == accountID
    }

    /// Blocking paywall fires only for the OWNER of an expired org — an org the
    /// user was merely invited to never paywalls them.
    var requiresSubscription: Bool {
        _ = revision
        return activeOrgIsOwned && activeOrganization?.subscriptionStatus == .expired
    }

    /// Trial banner shows only for the owner during their own org's trial.
    var showsTrialBanner: Bool {
        _ = revision
        return activeOrgIsOwned && activeOrganization?.subscriptionStatus == .trialing
    }

    var trialDaysRemaining: Int {
        activeOrganization?.trialDaysRemaining ?? 0
    }

    /// Effective storage limit (plan base + add-on) for the active org.
    var activeStorageLimit: Int64 {
        _ = revision
        return activeOrganization?.effectiveStorageBytes ?? PlanTier.basic.maxStorageBytes
    }

    var activeStorageAddOn: StorageAddOn {
        _ = revision
        return activeOrganization?.storageAddOn ?? .none
    }

    // MARK: - Mutations

    /// Subscribe the active org to a paid plan (mock payment). Routed through the
    /// session so the `revision` bump re-renders the root paywall gate; the
    /// underlying mutation lives on the SwiftData `Organization`.
    func subscribe(_ tier: PlanTier) {
        guard let org = activeOrganization else { return }
        OrganizationStore(context: context).subscribe(tier, for: org)
        revision += 1
    }

    /// Add/change/remove the active org's storage add-on (mock). Bumps `revision`
    /// so storage views re-render and the usage ring re-animates.
    func setStorageAddOn(_ addOn: StorageAddOn) {
        guard let org = activeOrganization else { return }
        OrganizationStore(context: context).setStorageAddOn(addOn, for: org)
        revision += 1
    }

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

    /// Re-evaluates the active organization after a cloud bootstrap/sync has
    /// upserted org + member rows (which the computed `organizations` fetch only
    /// sees once they exist). Picks the first available org if none is active.
    func reconcileActiveOrg() {
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
