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

    private enum Keys {
        static let account = "currentAccountID"
        static let org = "activeOrganizationID"
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
        normalizeActiveOrg()
    }

    // MARK: - Derived state

    var organizations: [Organization] {
        guard let account = currentAccount else { return [] }
        return OrganizationStore(context: context).organizations(for: account)
    }

    var activeOrganization: Organization? {
        OrganizationStore(context: context).organization(id: activeOrganizationID)
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

    func signOut() {
        currentAccount = nil
        activeOrganizationID = nil
        UserDefaults.standard.removeObject(forKey: Keys.account)
        UserDefaults.standard.removeObject(forKey: Keys.org)
        // Signing out restarts the journey from the welcome slides, not AuthView.
        UserDefaults.standard.set(false, forKey: Keys.hasSeenWelcome)
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
