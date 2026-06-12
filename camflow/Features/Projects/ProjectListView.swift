import SwiftUI
import SwiftData
import MapKit

struct ProjectListView: View {
    private enum SortMode: String, CaseIterable {
        case lastActivity = "Last Activity"
        case name = "Name"
    }

    @Environment(Session.self) private var session

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.updatedAt, order: .reverse)
    private var projects: [Project]

    @Query(filter: #Predicate<ProjectLabel> { $0.deletedAt == nil }, sort: \ProjectLabel.sortOrder)
    private var labels: [ProjectLabel]

    @State private var searchText = ""
    @State private var sortMode: SortMode = .lastActivity
    @State private var filterLabelID: UUID?
    @State private var isShowingEditor = false
    @State private var isShowingMap = false

    /// Projects owned by the active organization.
    private var orgProjects: [Project] {
        projects.filter { $0.organization?.id == session.activeOrganizationID }
    }

    private var filteredProjects: [Project] {
        var result = orgProjects
        if let filterLabelID {
            result = result.filter { $0.label?.id == filterLabelID }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedStandardContains(searchText)
                    || $0.address.localizedStandardContains(searchText)
            }
        }
        if sortMode == .name {
            result = result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if orgProjects.isEmpty {
                    ContentUnavailableView {
                        Label("No Projects Yet", systemImage: "folder.badge.plus")
                    } description: {
                        Text("Create a project for each job site to keep photos organized.")
                    } actions: {
                        Button("New Project") { isShowingEditor = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if isShowingMap {
                    ProjectMapView(projects: filteredProjects)
                        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                } else {
                    List(filteredProjects) { project in
                        NavigationLink(value: project) {
                            ProjectRow(project: project)
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: Project.self) { project in
                ProjectDetailView(project: project)
            }
            .searchable(text: $searchText, prompt: "Search projects")
            .toolbarBackground(isShowingMap ? .visible : .automatic, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingMap.toggle()
                    } label: {
                        Image(systemName: isShowingMap ? "list.bullet" : "map")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingEditor) {
                ProjectEditorView()
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortMode) {
                ForEach(SortMode.allCases, id: \.self) { mode in
                    Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                }
            }
            if !labels.isEmpty {
                Picker("Label", selection: $filterLabelID) {
                    Text("All Labels").tag(UUID?.none)
                    ForEach(labels) { label in
                        Text(label.name).tag(Optional(label.id))
                    }
                }
            }
        } label: {
            Image(systemName: filterLabelID == nil
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
        }
    }
}

struct ProjectRow: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(project.name)
                    .font(.headline)
                if let label = project.label {
                    LabelChip(name: label.name, colorHex: label.colorHex)
                }
            }
            if !project.address.isEmpty {
                Text(project.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text("^[\(project.activePhotos.count) photo](inflect: true) · \(project.updatedAt, format: .relative(presentation: .named))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

/// Map of all projects with coordinates. Phase 4 adds clustering.
struct ProjectMapView: View {
    let projects: [Project]

    @State private var selectedProjectID: UUID?

    private var mappableProjects: [Project] {
        projects.filter(\.hasCoordinate)
    }

    private var selectedProject: Project? {
        mappableProjects.first { $0.id == selectedProjectID }
    }

    var body: some View {
        Map(selection: $selectedProjectID) {
            ForEach(mappableProjects) { project in
                Marker(project.name, systemImage: "folder.fill",
                       coordinate: CLLocationCoordinate2D(latitude: project.latitude!, longitude: project.longitude!))
                    .tint(project.label.map { Color(hex: $0.colorHex) } ?? .orange)
                    .tag(project.id)
            }
        }
        .overlay(alignment: .bottom) {
            if let project = selectedProject {
                NavigationLink(value: project) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(.headline)
                            if !project.address.isEmpty {
                                Text(project.address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding()
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Project.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ProjectListView()
        .modelContainer(container)
        .environment(LocationService())
        .environment(Session(context: container.mainContext))
}
