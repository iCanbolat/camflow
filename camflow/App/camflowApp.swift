import SwiftUI
import SwiftData
import CoreServices

@main
struct CamFlowApp: App {
    @State private var locationService = LocationService()
    @State private var session: Session

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
            BeforeAfterPair.self,
            Measurement.self,
            Account.self,
            Organization.self,
            OrgMember.self,
            TaskComment.self,
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
            RootCoordinatorView()
                .environment(locationService)
                .environment(session)
                .onOpenURL { handle(url: $0) }
                // Universal links also arrive via onOpenURL in the SwiftUI
                // lifecycle; this covers the NSUserActivity delivery path.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { handle(url: url) }
                }
        }
        .modelContainer(container)
    }

    /// Routes incoming invite links (camflow:// and https://camflow.app);
    /// `RootCoordinatorView` reacts to the pending code.
    private func handle(url: URL) {
        if let code = InviteLinks.code(from: url) {
            session.setPendingInvite(code: code)
        }
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
