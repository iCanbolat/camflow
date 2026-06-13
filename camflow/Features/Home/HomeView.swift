import SwiftUI
import SwiftData

/// Activity feed across all projects: photos grouped by day and project,
/// plus completed tasks and generated reports as activity rows.
struct HomeView: View {
    @Environment(Session.self) private var session

    @Query(filter: #Predicate<Photo> { $0.deletedAt == nil }, sort: \Photo.capturedAt, order: .reverse)
    private var allPhotos: [Photo]

    @Query(filter: #Predicate<ProjectTask> { $0.deletedAt == nil && $0.completedAt != nil })
    private var allCompletedTasks: [ProjectTask]

    @Query(filter: #Predicate<Report> { $0.deletedAt == nil }, sort: \Report.createdAt, order: .reverse)
    private var allReports: [Report]

    // Persisted notifications for the current member (filtered in Swift).
    @Query(filter: #Predicate<AppNotification> { $0.deletedAt == nil }, sort: \AppNotification.createdAt, order: .reverse)
    private var allNotifications: [AppNotification]

    @State private var previewingReport: Report?
    @State private var isShowingCreateOrg = false
    @State private var isShowingNotifications = false

    // MARK: - Active-org scoping

    private var activeOrgID: UUID? { session.activeOrganizationID }

    private var photos: [Photo] {
        allPhotos.filter { $0.project?.organization?.id == activeOrgID }
    }

    private var completedTasks: [ProjectTask] {
        allCompletedTasks.filter { $0.project?.organization?.id == activeOrgID }
    }

    private var reports: [Report] {
        allReports.filter { $0.project?.organization?.id == activeOrgID }
    }

    // MARK: - Feed assembly

    private struct ProjectGroup: Identifiable {
        let id: String
        let project: Project?
        let photos: [Photo]
    }

    private enum Activity: Identifiable {
        case taskCompleted(ProjectTask)
        case reportCreated(Report)

        var id: UUID {
            switch self {
            case .taskCompleted(let task): task.id
            case .reportCreated(let report): report.id
            }
        }

        var date: Date {
            switch self {
            case .taskCompleted(let task): task.completedAt ?? task.updatedAt
            case .reportCreated(let report): report.createdAt
            }
        }
    }

    private struct DaySection: Identifiable {
        let id: Date
        let groups: [ProjectGroup]
        let activities: [Activity]
    }

    private var isEmpty: Bool {
        photos.isEmpty && completedTasks.isEmpty && reports.isEmpty
    }

    // MARK: - Notifications

    private var myNotifications: [AppNotification] {
        guard let memberID = session.activeMembership?.id else { return [] }
        return allNotifications.filter { $0.recipient?.id == memberID }
    }

    private var unreadNotificationCount: Int {
        myNotifications.filter { !$0.isRead }.count
    }

    private var sections: [DaySection] {
        let calendar = Calendar.current
        let photosByDay = Dictionary(grouping: photos) { calendar.startOfDay(for: $0.capturedAt) }

        var activitiesByDay: [Date: [Activity]] = [:]
        for task in completedTasks {
            let day = calendar.startOfDay(for: task.completedAt ?? task.updatedAt)
            activitiesByDay[day, default: []].append(.taskCompleted(task))
        }
        for report in reports {
            let day = calendar.startOfDay(for: report.createdAt)
            activitiesByDay[day, default: []].append(.reportCreated(report))
        }

        let allDays = Set(photosByDay.keys).union(activitiesByDay.keys)
        return allDays.sorted(by: >).map { day in
            let byProject = Dictionary(grouping: photosByDay[day] ?? []) { $0.project?.id }
            let groups = byProject.values
                .map { groupPhotos in
                    ProjectGroup(
                        id: "\(day.timeIntervalSinceReferenceDate)-\(groupPhotos.first?.project?.id.uuidString ?? "unassigned")",
                        project: groupPhotos.first?.project,
                        photos: groupPhotos.sorted { $0.capturedAt > $1.capturedAt }
                    )
                }
                .sorted { ($0.photos.first?.capturedAt ?? .distantPast) > ($1.photos.first?.capturedAt ?? .distantPast) }
            let activities = (activitiesByDay[day] ?? []).sorted { $0.date > $1.date }
            return DaySection(id: day, groups: groups, activities: activities)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isEmpty {
                    ContentUnavailableView {
                        Label("Welcome to CamFlow", systemImage: "camera.viewfinder")
                    } description: {
                        Text("Capture your first photo with the camera tab and your activity will show up here.")
                    }
                } else {
                    List {
                        ForEach(sections) { section in
                            Section(section.id.dayGroupTitle) {
                                ForEach(section.groups) { group in
                                    groupRow(group)
                                }
                                ForEach(section.activities) { activity in
                                    activityRow(activity)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    orgSwitcher
                }
                ToolbarItem(placement: .topBarTrailing) {
                    notificationBell
                }
            }
            .sheet(isPresented: $isShowingNotifications) {
                NotificationsView(recipientID: session.activeMembership?.id ?? UUID())
            }
            .sheet(isPresented: $isShowingCreateOrg) {
                CreateOrganizationView(isModal: true)
            }
            .navigationDestination(for: Project.self) { project in
                ProjectDetailView(project: project)
            }
            .navigationDestination(for: ProjectTask.self) { task in
                TaskDetailView(task: task)
            }
            .navigationDestination(for: Photo.self) { photo in
                let groupPhotos = sections
                    .flatMap(\.groups)
                    .first { $0.photos.contains { $0.id == photo.id } }?
                    .photos ?? [photo]
                PhotoViewerView(
                    photos: groupPhotos,
                    initialIndex: groupPhotos.firstIndex { $0.id == photo.id } ?? 0
                )
            }
            .sheet(item: $previewingReport) { report in
                if let project = report.project {
                    ReportPreviewSheet(report: report, project: project)
                }
            }
        }
    }

    // MARK: - Notification bell

    private var notificationBell: some View {
        Button {
            isShowingNotifications = true
        } label: {
            Image(systemName: "bell")
                .padding(5)
                .overlay(alignment: .topTrailing) {
                    if unreadNotificationCount > 0 {
                        Text(unreadNotificationCount > 99 ? "99+" : "\(unreadNotificationCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.red, in: Capsule())
                            .frame(minWidth: 16)
                    }
                }
        }
        .accessibilityLabel(Text("Notifications"))
    }

    // MARK: - Org switcher

    private var orgSwitcher: some View {
        Menu {
            ForEach(session.organizations) { org in
                Button {
                    session.switchTo(org)
                } label: {
                    if org.id == activeOrgID {
                        Label(org.name, systemImage: "checkmark")
                    } else {
                        Text(org.name)
                    }
                }
            }
            Divider()
            Button {
                isShowingCreateOrg = true
            } label: {
                Label("Create Organization", systemImage: "plus")
            }
            Button {
                // Future: accept an invite to join another org from the cloud phase.
            } label: {
                Label("Join with code…", systemImage: "person.badge.key")
            }
            .disabled(true)
        } label: {
            HStack(spacing: 4) {
                Text(session.activeOrganization?.name ?? String(localized: "CamFlow"))
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Rows

    private func groupRow(_ group: ProjectGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let project = group.project {
                NavigationLink(value: project) {
                    groupHeader(name: project.name, label: project.label, count: group.photos.count)
                }
                .buttonStyle(.plain)
            } else {
                groupHeader(name: String(localized: "Unassigned"), label: nil, count: group.photos.count)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(group.photos.prefix(15)) { photo in
                        NavigationLink(value: photo) {
                            PhotoCell(photo: photo)
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func groupHeader(name: String, label: ProjectLabel?, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.subheadline.weight(.semibold))
            if let label {
                LabelChip(name: label.name, colorHex: label.colorHex)
            }
            Spacer()
            Text("^[\(count) item](inflect: true)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func activityRow(_ activity: Activity) -> some View {
        switch activity {
        case .taskCompleted(let task):
            NavigationLink(value: task) {
                activityContent(
                    systemImage: "checkmark.circle.fill",
                    iconColor: .green,
                    title: task.title,
                    subtitle: activitySubtitle(prefix: String(localized: "Task completed"), project: task.project, date: activity.date)
                ) {
                    if let assignee = task.assignee, assignee.deletedAt == nil {
                        MemberAvatar(member: assignee, size: 26)
                    }
                }
            }
            .buttonStyle(.plain)
        case .reportCreated(let report):
            Button {
                previewingReport = report
            } label: {
                activityContent(
                    systemImage: "doc.richtext.fill",
                    iconColor: .accentColor,
                    title: report.title,
                    subtitle: activitySubtitle(prefix: String(localized: "Report created"), project: report.project, date: activity.date)
                ) {
                    Text("^[\(report.photoIDs.count) photo](inflect: true)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func activitySubtitle(prefix: String, project: Project?, date: Date) -> String {
        var parts = [prefix]
        if let project {
            parts.append(project.name)
        }
        parts.append(date.formatted(.dateTime.hour().minute()))
        return parts.joined(separator: " · ")
    }

    private func activityContent<Trailing: View>(
        systemImage: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            trailing()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Photo.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return HomeView()
        .modelContainer(container)
        .environment(Session(context: container.mainContext))
}
