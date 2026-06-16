import SwiftUI
import SwiftData

/// Gates the app: Welcome slides → Auth → Join (pending invite) / Create
/// organization → Permissions → the main tab UI. Each step is driven by a
/// persisted flag or `Session` state, so re-launching resumes wherever the
/// user left off.
struct RootCoordinatorView: View {
    @Environment(Session.self) private var session

    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("hasPrimedPermissions") private var hasPrimedPermissions = false

    var body: some View {
        if !hasSeenWelcome {
            WelcomeView { hasSeenWelcome = true }
        } else if session.currentAccount == nil {
            AuthView()
        } else if let code = session.pendingInviteCode {
            // An invited user is never forced into org creation; accepting or
            // declining clears the code and falls through to the next gate.
            JoinOrganizationView(code: code)
        } else if session.activeOrganizationID == nil {
            // `activeOrganizationID` is observable state (unlike the computed
            // `organizations` fetch), so creating the first org re-renders this
            // gate. `Session.normalizeActiveOrg` guarantees it is non-nil
            // whenever the account has at least one organization.
            CreateOrganizationView()
        } else if !hasPrimedPermissions {
            PermissionPrimingView { hasPrimedPermissions = true }
        } else if session.requiresSubscription {
            // The owner's trial has ended with no subscription — a blocking gate
            // forces a plan choice. Scoped to owned orgs, so invited members of an
            // expired org are never blocked here.
            PaywallView()
        } else {
            RootTabView()
        }
    }
}
