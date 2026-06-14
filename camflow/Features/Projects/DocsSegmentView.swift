import SwiftUI

/// "Docs" segment of project detail. Hosts two sub-tabs: rich block **Pages**
/// and the existing PDF **Reports** flow. Only the active sub-view is in the
/// view tree, so each keeps its own toolbar `+` with no conflict.
struct DocsSegmentView: View {
    @Bindable var project: Project

    private enum Tab: String, CaseIterable {
        case pages = "Pages"
        case reports = "Reports"
    }

    @State private var tab: Tab = .pages

    var body: some View {
        VStack(spacing: 0) {
            Picker("Document type", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(LocalizedStringKey(tab.rawValue)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 32)
            .padding(.bottom, 8)

            switch tab {
            case .pages:
                PagesSegmentView(project: project)
            case .reports:
                ReportsSegmentView(project: project)
            }
        }
    }
}
