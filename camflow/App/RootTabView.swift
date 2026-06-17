import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case home
    case projects
    case capture
    case team
    case more
}

struct RootTabView: View {
    @Environment(Session.self) private var session
    @Environment(AppServices.self) private var services
    @State private var selection: AppTab = {
        #if DEBUG
        if let tab = DebugSupport.initialTab { return tab }
        #endif
        return .home
    }()
    @State private var isShowingCamera = false
    #if DEBUG
    @State private var isShowingDebugScreen = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            SyncStatusBanner(
                state: services.syncEngine.state,
                isOnline: services.networkMonitor.isOnline,
                onRetry: { services.syncNow() }
            )
            .animation(.easeInOut(duration: 0.25), value: services.syncEngine.state)
            .animation(.easeInOut(duration: 0.25), value: services.networkMonitor.isOnline)

            tabView
        }
    }

    private var tabView: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("Projects", systemImage: "folder.fill", value: AppTab.projects) {
                ProjectListView()
            }
            // Selecting this tab never sticks — it launches the full-screen camera.
            Tab("Capture", systemImage: "camera.fill", value: AppTab.capture) {
                Color.clear
            }
            Tab("Team", systemImage: "person.2.fill", value: AppTab.team) {
                TeamView()
            }
            Tab("More", systemImage: "ellipsis.circle.fill", value: AppTab.more) {
                MoreView()
            }
        }
        .onChange(of: selection) { oldValue, newValue in
            if newValue == .capture {
                selection = oldValue
                isShowingCamera = true
            }
        }
        // A notification deep-link tap surfaces notifications from the Home tab.
        .onChange(of: session.notificationsRequest) { _, _ in
            selection = .home
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CaptureView()
        }
        #if DEBUG
        .fullScreenCover(isPresented: $isShowingDebugScreen) {
            if let kind = DebugSupport.debugScreen {
                DebugScreenHost(kind: kind)
            }
        }
        .task {
            if DebugSupport.debugScreen != nil {
                try? await Task.sleep(for: .seconds(0.5))
                isShowingDebugScreen = true
            }
        }
        #endif
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Project.self, inMemory: true)
        .environment(LocationService())
}
