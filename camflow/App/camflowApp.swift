import SwiftUI
import SwiftData
import CoreServices

@main
struct CamFlowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var locationService = LocationService()
    @State private var session: Session
    @State private var services: AppServices
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer

    init() {
        let schema = Schema([
            Project.self,
            Photo.self,
            Tag.self,
            ProjectLabel.self,
            ProjectTask.self,
            ChecklistTemplate.self,
            Checklist.self,
            ChecklistItem.self,
            Report.self,
            Page.self,
            BeforeAfterPair.self,
            Measurement.self,
            Account.self,
            Organization.self,
            OrgMember.self,
            TaskComment.self,
            PhotoComment.self,
            AppNotification.self,
            MediaUpload.self,
        ])
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
        self.container = container
        let session = Session(context: container.mainContext)
        _session = State(initialValue: session)
        _services = State(initialValue: AppServices(modelContext: container.mainContext, session: session))

        // Runs before the first render so the UI never shows pre-seed /
        // pre-override state (the debug role/plan args mutate rows the views
        // have already read if this happens in `.task`).
        Self.seedDefaultLabelsIfNeeded(context: container.mainContext)
        #if DEBUG
        DebugSupport.seedSampleDataIfRequested(context: container.mainContext)
        DebugSupport.applyAuthSkipIfRequested(session: session, context: container.mainContext)
        DebugSupport.applyInviteURLIfRequested(session: session)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootCoordinatorView()
                    .environment(locationService)
                    .environment(session)
                    .environment(services)
                    .task {
                        // Wire forced-sign-out, then refresh from the cloud on
                        // cold launch (local-first UI is already on screen).
                        await services.start()
                        await services.hydrate()
                    }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active {
                            // Sync + (re)open the realtime stream on foreground,
                            // and free stale on-device media (throttled daily).
                            services.syncNow()
                            services.connectRealtime()
                            services.purgeStaleMediaIfDue()
                        } else {
                            // Suspend the SSE stream while backgrounded.
                            services.disconnectRealtime()
                        }
                    }
                    .onOpenURL { handle(url: $0) }
                    // Universal links also arrive via onOpenURL in the SwiftUI
                    // lifecycle; this covers the NSUserActivity delivery path.
                    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                        if let url = activity.webpageURL { handle(url: url) }
                    }

                if showSplash {
                    SplashView {
                        withAnimation(.easeInOut(duration: 0.45)) { showSplash = false }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
        }
        .modelContainer(container)
    }

    /// Routes incoming URLs — invite links (camflow:// and https://camflow.app)
    /// and notification deep links — through the shared handler.
    /// `RootCoordinatorView`/`HomeView` react to the resulting `Session` state.
    private func handle(url: URL) {
        services.handleDeepLink(url)
    }

    /// First-launch convenience: a starter set of project status labels.
    @MainActor
    private static func seedDefaultLabelsIfNeeded(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<ProjectLabel>())) ?? 0
        guard count == 0 else { return }
        let defaults: [(String, String)] = [
            ("Active", "#2E933C"),
            ("On Hold", "#F7B32B"),
            ("Completed", "#1B98E0"),
        ]
        for (index, (name, hex)) in defaults.enumerated() {
            context.insert(ProjectLabel(name: name, colorHex: hex, sortOrder: index))
        }
    }
}
