import SwiftUI
import SwiftData

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
        _session = State(initialValue: Session(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootCoordinatorView()
                .environment(locationService)
                .environment(session)
                .task {
                    seedDefaultLabelsIfNeeded()
                    #if DEBUG
                    DebugSupport.seedSampleDataIfRequested(context: container.mainContext)
                    DebugSupport.applyAuthSkipIfRequested(session: session, context: container.mainContext)
                    #endif
                }
        }
        .modelContainer(container)
    }

    /// First-launch convenience: a starter set of project status labels.
    @MainActor
    private func seedDefaultLabelsIfNeeded() {
        let context = container.mainContext
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
