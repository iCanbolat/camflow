import Foundation
import SwiftData
import Observation

/// Dependency container for the cloud layer. Created once at app start, owns the
/// networking actors and the cloud-backed services, and is injected via
/// `.environment` so views read `authService`/`inviteService`/`memberService`
/// instead of constructing mocks. Also drives bootstrap (hydrate orgs + members)
/// and sign-out (revoke + local wipe).
@MainActor
@Observable
final class AppServices {
    let modelContext: ModelContext
    let networkMonitor: NetworkMonitor
    let tokenStore: TokenStore
    let authService: any AuthService
    let inviteService: any InviteService
    let memberService: ApiMemberService
    let syncEngine: SyncEngine
    let mediaUploader: MediaUploader
    let mediaProvider: MediaProvider
    let realtimeClient: RealtimeClient
    let pushService: PushService
    private let mediaRetention: MediaRetention

    enum BootstrapState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var bootstrapState: BootstrapState = .idle

    private let api: APIClient
    private let interceptor: AuthInterceptor
    private let session: Session

    init(modelContext: ModelContext, session: Session) {
        self.modelContext = modelContext
        self.session = session

        let tokens = TokenStore()
        let interceptor = AuthInterceptor(tokens: tokens)
        let api = APIClient(tokens: tokens, interceptor: interceptor)

        self.tokenStore = tokens
        self.interceptor = interceptor
        self.api = api
        let monitor = NetworkMonitor()
        self.networkMonitor = monitor
        self.authService = ApiAuthService(api: api, tokens: tokens, context: modelContext)
        self.inviteService = ApiInviteService(api: api, context: modelContext)
        self.memberService = ApiMemberService(api: api, context: modelContext)

        // The sync engine works a background context over the same container so
        // batch upserts never block the main `@Query` UI.
        let syncActor = SyncActor(modelContainer: modelContext.container)
        self.syncEngine = SyncEngine(api: api, syncActor: syncActor, monitor: monitor, tokens: tokens)

        // Media: background-URLSession uploader (enqueued via `MediaUpload` rows)
        // + local-first retrieval/cache for display.
        self.mediaUploader = MediaUploader(api: api, context: modelContext, tokens: tokens)
        self.mediaProvider = MediaProvider(api: api)

        // Realtime SSE → debounced pull; APNs registration + notification actions.
        self.realtimeClient = RealtimeClient(tokens: tokens, interceptor: interceptor, monitor: monitor)
        self.pushService = PushService(api: api, tokens: tokens)
        self.mediaRetention = MediaRetention(context: modelContext, tokens: tokens)
    }

    /// Period between background sync cycles. The loop re-reads the active org
    /// each tick, so an org switch is picked up within this window.
    private static let syncInterval: TimeInterval = 45

    /// Wires the forced-sign-out signal: when a refresh ultimately fails the
    /// interceptor clears the tokens and calls this, which routes back to auth.
    func start() async {
        await interceptor.setSignOutHandler { [weak self] in
            Task { @MainActor in self?.handleForcedSignOut() }
        }
        // Once a cycle finishes, the just-pushed photo rows exist server-side, so
        // their queued media can safely upload (commit hits the update path); and
        // the app badge reflects the freshly-pulled unread count.
        syncEngine.onCycleComplete = { [weak self] in
            self?.uploadPendingMedia()
            self?.refreshBadge()
        }
        syncEngine.startPeriodic(every: Self.syncInterval) { [weak session] in
            session?.activeOrganizationID
        }

        // Push: APNs token → /devices, notification taps → deep-link routing.
        PushBridge.shared.setTokenHandler { [weak self] data in
            Task { await self?.pushService.registerDevice(tokenData: data) }
        }
        PushBridge.shared.setDeepLinkHandler { [weak self] url in
            self?.handleDeepLink(url)
        }
        realtimeClient.onChange = { [weak self] in self?.syncNow() }

        // Flush the outbox the moment connectivity returns.
        networkMonitor.onChange = { [weak self] online in
            guard online else { return }
            self?.syncNow()
            self?.connectRealtime()
        }

        uploadPendingMedia()
        await pushService.registerIfAuthorized()
        connectRealtime()
        purgeStaleMediaIfDue()
    }

    /// Frees old on-device media bytes (kept in the cloud; re-downloaded on
    /// demand). Throttled to once/day; safe to call on launch + foreground.
    func purgeStaleMediaIfDue() {
        Task { await mediaRetention.purgeIfDue() }
    }

    // MARK: - Realtime lifecycle

    /// Opens (or re-points) the SSE stream to the active org. Called on launch,
    /// foreground, and after bootstrap; idempotent.
    func connectRealtime() {
        realtimeClient.connect(organizationID: session.activeOrganizationID)
    }

    func disconnectRealtime() {
        realtimeClient.stop()
    }

    // MARK: - Push & notifications

    /// Notification-permission priming entry point (called from the priming view).
    func requestPushAuthorization() async {
        await pushService.requestAuthorization()
    }

    /// Marks a notification read locally and server-side (notifications aren't a
    /// sync push entity, so the server call is what persists the read state), then
    /// refreshes the badge.
    func markNotificationRead(_ notification: AppNotification) {
        let id = notification.id
        NotificationStore(context: modelContext).markRead(notification)
        refreshBadge()
        Task { await pushService.markRead(notificationID: id) }
    }

    func markAllNotificationsRead(_ notifications: [AppNotification]) {
        NotificationStore(context: modelContext).markAllRead(notifications)
        refreshBadge()
        if let orgID = session.activeOrganizationID {
            Task { await pushService.markAllRead(organizationID: orgID) }
        }
    }

    /// App-icon badge = unread notifications for the active membership.
    func refreshBadge() {
        guard let memberID = session.activeMembership?.id else {
            pushService.setBadge(0)
            return
        }
        let descriptor = FetchDescriptor<AppNotification>(
            predicate: #Predicate { $0.deletedAt == nil && $0.isRead == false }
        )
        let unread = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.recipient?.id == memberID }
        pushService.setBadge(unread.count)
    }

    /// Single entry point for incoming URLs (invite links + notification deep
    /// links). Invite codes route to the join flow; any other `camflow://` link
    /// opens the notifications surface.
    func handleDeepLink(_ url: URL) {
        if let code = InviteLinks.code(from: url) {
            session.setPendingInvite(code: code)
            return
        }
        if url.scheme?.lowercased() == InviteLinks.customScheme {
            session.requestNotifications()
        }
    }

    /// Foreground / org-switch / "Sync now" trigger for the active org. Also
    /// flushes any pending media uploads.
    func syncNow() {
        syncEngine.requestSync(organizationID: session.activeOrganizationID)
        uploadPendingMedia()
    }

    /// Starts/resumes background media uploads (no-op without a cloud session).
    func uploadPendingMedia() {
        Task { await mediaUploader.processPending() }
    }

    /// Requeues a photo's server-side media processing (e.g. after a failure).
    func reprocessMedia(_ photo: Photo) async throws {
        guard let orgID = photo.project?.organization?.id ?? session.activeOrganizationID else { return }
        let body = MediaScopeBody(organizationId: orgID)
        let _: CommitUploadDTO = try await api.send(.post("/media/\(photo.id.uuidString)/reprocess", json: body))
        photo.processingStatus = .queued
        try? modelContext.save()
    }

    // MARK: - Bootstrap

    /// Pulls the account's organizations and their member rosters into SwiftData
    /// so memberships/roles resolve. Best-effort and idempotent: safe to call on
    /// cold launch and right after sign-in. No-op without a stored session.
    func hydrate() async {
        guard await tokenStore.hasSession else { return }
        bootstrapState = .loading
        do {
            let orgs: [OrganizationDTO] = try await api.send(.get("/organizations"))
            for dto in orgs {
                guard !hasLocalEdits(orgID: dto.id) else { continue }
                CloudMappers.upsertOrganization(dto, in: modelContext)
            }
            try? modelContext.save()
            session.reconcileActiveOrg()

            for dto in orgs {
                guard let members: [MemberDTO] = try? await api.send(
                    .get("/organizations/\(dto.id)/members")
                ) else { continue }
                for member in members {
                    guard !hasLocalEdits(memberID: member.id) else { continue }
                    CloudMappers.upsertMember(member, in: modelContext)
                }
            }
            try? modelContext.save()
            session.reconcileActiveOrg()
            bootstrapState = .ready
            // Push any offline edits and pull the full delta for the active org,
            // and open the realtime stream now that the active org is known.
            syncNow()
            connectRealtime()
        } catch {
            bootstrapState = .failed((error as? APIError)?.userMessage ?? error.localizedDescription)
        }
    }

    // MARK: - Sign-out

    /// Revokes the refresh-token family server-side, then clears tokens and wipes
    /// the local store (cloud is the source of truth; the next sign-in re-pulls).
    func signOut() async {
        // Stop receiving pushes on this install + close the realtime stream while
        // the session is still valid.
        await pushService.unregisterDevice()
        disconnectRealtime()
        if let refresh = await tokenStore.refreshToken,
           let endpoint = try? Endpoint.post("/auth/sign-out", json: RefreshBody(refreshToken: refresh)) {
            // Typed `Void?` selects the no-content `send` overload unambiguously.
            let _: Void? = try? await api.send(endpoint)
        }
        await tokenStore.clear()
        // Route to auth first (unmounts the tab UI), then wipe the local rows.
        session.signOut()
        wipeLocalStore()
        bootstrapState = .idle
    }

    private func handleForcedSignOut() {
        // The interceptor already cleared the tokens; route to auth, then wipe.
        disconnectRealtime()
        session.signOut()
        wipeLocalStore()
        bootstrapState = .idle
    }

    // MARK: - Organization creation

    /// Creates the org on the backend (which also inserts the owner member row),
    /// then upserts both locally so `Session.activeMembership` resolves.
    func createOrganization(name: String) async throws -> Organization {
        let body = CreateOrganizationBody(id: UUID(), name: name, phone: nil, email: nil, website: nil)
        let dto: OrganizationDTO = try await api.send(.post("/organizations", json: body))
        let org = CloudMappers.upsertOrganization(dto, in: modelContext)
        if let members: [MemberDTO] = try? await api.send(.get("/organizations/\(org.id)/members")) {
            for member in members { CloudMappers.upsertMember(member, in: modelContext) }
        }
        try? modelContext.save()
        // Pull the new org's server-side rows (owner member, defaults).
        syncEngine.requestSync(organizationID: org.id)
        return org
    }

    // MARK: - Local-edit guards

    /// A pull must not clobber rows the user changed offline (a coarse LWW until
    /// Phase 2's push reconciles by `updatedAt`).
    private func hasLocalEdits(orgID: UUID) -> Bool {
        guard let org = CloudMappers.organization(id: orgID, in: modelContext) else { return false }
        return org.syncStatus != .synced
    }

    private func hasLocalEdits(memberID: UUID) -> Bool {
        var descriptor = FetchDescriptor<OrgMember>(predicate: #Predicate { $0.id == memberID })
        descriptor.fetchLimit = 1
        guard let member = (try? modelContext.fetch(descriptor))?.first else { return false }
        return member.syncStatus != .synced
    }

    /// Deletes every local row and cached media file. The next sign-in/hydrate
    /// re-pulls from the cloud, so nothing is permanently lost.
    private func wipeLocalStore() {
        try? modelContext.delete(model: Photo.self)
        try? modelContext.delete(model: PhotoComment.self)
        try? modelContext.delete(model: Tag.self)
        try? modelContext.delete(model: ProjectLabel.self)
        try? modelContext.delete(model: ProjectTask.self)
        try? modelContext.delete(model: TaskComment.self)
        try? modelContext.delete(model: ChecklistTemplate.self)
        try? modelContext.delete(model: Checklist.self)
        try? modelContext.delete(model: ChecklistItem.self)
        try? modelContext.delete(model: Report.self)
        try? modelContext.delete(model: Page.self)
        try? modelContext.delete(model: BeforeAfterPair.self)
        try? modelContext.delete(model: Measurement.self)
        try? modelContext.delete(model: Project.self)
        try? modelContext.delete(model: OrgMember.self)
        try? modelContext.delete(model: Organization.self)
        try? modelContext.delete(model: AppNotification.self)
        try? modelContext.delete(model: MediaUpload.self)
        try? modelContext.delete(model: Account.self)
        try? modelContext.save()

        FileStorage.clear(.photos)
        FileStorage.clear(.branding)
        FileStorage.clear(.reports)
        FileStorage.clear(.pages)

        // Drop every delta cursor so the next account bootstraps from scratch.
        syncEngine.resetCursors()
    }
}
