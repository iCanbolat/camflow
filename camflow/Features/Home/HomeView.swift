import SwiftUI
import SwiftData

/// Activity feed across all projects: photos grouped by day and project,
/// plus completed tasks and generated reports as activity rows. The feed is
/// limited to the last 7 days (today and the previous six); the dashboard KPIs
/// above it are unaffected by this window.
struct HomeView: View {
    @Environment(Session.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(filter: #Predicate<Photo> { $0.deletedAt == nil }, sort: \Photo.capturedAt, order: .reverse)
    private var allPhotos: [Photo]

    @Query(filter: #Predicate<ProjectTask> { $0.deletedAt == nil && $0.completedAt != nil })
    private var allCompletedTasks: [ProjectTask]

    // Open (not yet completed) tasks; scoped to the active org and current
    // member in Swift below — optional relationship chains aren't predicate-safe.
    @Query(filter: #Predicate<ProjectTask> { $0.deletedAt == nil && $0.completedAt == nil })
    private var allOpenTasks: [ProjectTask]

    @Query(filter: #Predicate<Report> { $0.deletedAt == nil }, sort: \Report.createdAt, order: .reverse)
    private var allReports: [Report]

    // Used only to detect whether the active org has any projects yet.
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil })
    private var allProjects: [Project]

    // Persisted notifications for the current member (filtered in Swift).
    @Query(filter: #Predicate<AppNotification> { $0.deletedAt == nil }, sort: \AppNotification.createdAt, order: .reverse)
    private var allNotifications: [AppNotification]

    @State private var previewingReport: Report?
    @State private var isShowingCreateOrg = false
    @State private var isShowingCreateProject = false
    @State private var isShowingNotifications = false
    @State private var isShowingSearch = false
    @State private var isShowingPlans = false

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

    /// True when the active organization has no projects yet — drives the
    /// "create your first project" prompt instead of the activity feed.
    private var orgHasNoProjects: Bool {
        !allProjects.contains { $0.organization?.id == activeOrgID }
    }

    /// Open tasks assigned to the current member in the active org, overdue first.
    private var myOpenTasks: [ProjectTask] {
        guard let memberID = session.activeMembership?.id else { return [] }
        return allOpenTasks
            .filter { $0.project?.organization?.id == activeOrgID }
            .filter { $0.assignee?.id == memberID }
            .sorted { lhs, rhs in
                if lhs.isOverdue != rhs.isOverdue { return lhs.isOverdue }
                let l = lhs.dueDate ?? .distantFuture
                let r = rhs.dueDate ?? .distantFuture
                return l != r ? l < r : lhs.createdAt > rhs.createdAt
            }
    }

    // MARK: - Dashboard

    private var photosTodayCount: Int {
        photos.filter { Calendar.current.isDateInToday($0.capturedAt) }.count
    }

    private var openTaskCount: Int { myOpenTasks.count }

    private var overdueCount: Int { myOpenTasks.filter(\.isOverdue).count }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: String(localized: "Good morning")
        case 12..<18: String(localized: "Good afternoon")
        default: String(localized: "Good evening")
        }
    }

    private var firstName: String {
        (session.currentAccount?.displayName ?? "")
            .split(separator: " ").first.map(String.init) ?? ""
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

    /// Start of the feed window: the last 7 days (today and the previous six).
    private var feedStartDay: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now))
            ?? .distantPast
    }

    private var sections: [DaySection] {
        let calendar = Calendar.current
        let cutoff = feedStartDay
        let recentPhotos = photos.filter { $0.capturedAt >= cutoff }
        let photosByDay = Dictionary(grouping: recentPhotos) { calendar.startOfDay(for: $0.capturedAt) }

        var activitiesByDay: [Date: [Activity]] = [:]
        for task in completedTasks {
            let date = task.completedAt ?? task.updatedAt
            guard date >= cutoff else { continue }
            activitiesByDay[calendar.startOfDay(for: date), default: []].append(.taskCompleted(task))
        }
        for report in reports {
            guard report.createdAt >= cutoff else { continue }
            activitiesByDay[calendar.startOfDay(for: report.createdAt), default: []].append(.reportCreated(report))
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
            List {
                if session.showsTrialBanner {
                    Section {
                        trialBanner
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        greetingHeader
                        kpiTiles
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if !myOpenTasks.isEmpty {
                    Section(String(localized: "Assigned to you")) {
                        ForEach(myOpenTasks.prefix(8)) { task in
                            assignedTaskRow(task)
                        }
                    }
                }

                if orgHasNoProjects {
                    Section {
                        createProjectCTA
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if sections.isEmpty {
                    Section {
                        if isEmpty {
                            welcomeHintRow
                        } else {
                            noRecentActivityRow
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
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
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background { ambientBackground }
            .contentMargins(.top, 8, for: .scrollContent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(Text("Search"))
                }
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
            .sheet(isPresented: $isShowingPlans) {
                NavigationStack { PlanBillingView() }
            }
            .sheet(isPresented: $isShowingCreateProject) {
                ProjectEditorView()
            }
            .sheet(isPresented: $isShowingSearch) {
                PhotoSearchView()
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

    // MARK: - Dashboard views

    /// Warm ambient wash that fades from the top of the screen to about the
    /// middle. Sits over the standard grouped background so the list cards still
    /// read normally; opacity is tuned per appearance (a touch stronger on the
    /// dark base, softer on the light one).
    private var ambientBackground: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(colorScheme == .dark ? 0.34 : 0.22),
                    Color.accentColor.opacity(colorScheme == .dark ? 0.10 : 0.07),
                    .clear,
                ],
                startPoint: .top,
                endPoint: .center
            )
            .blur(radius: 24)
        }
        .ignoresSafeArea()
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(firstName.isEmpty ? greeting : "\(greeting), \(firstName)")
                .font(.title2.weight(.bold))
            Text(Date.now.formatted(date: .complete, time: .omitted))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiTiles: some View {
        HStack(spacing: 10) {
            kpiTile(value: photosTodayCount, label: "Photos today",
                    systemImage: "camera.fill", tint: .accentColor)
            kpiTile(value: openTaskCount, label: "Open tasks",
                    systemImage: "checklist", tint: .blue)
            kpiTile(value: overdueCount, label: "Overdue",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: overdueCount > 0 ? .red : .secondary)
        }
    }

    private func kpiTile(value: Int, label: LocalizedStringKey, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.title.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func assignedTaskRow(_ task: ProjectTask) -> some View {
        NavigationLink(value: task) {
            HStack(spacing: 12) {
                Button {
                    TaskStore(context: modelContext).toggleCompletion(task)
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let project = task.project {
                            Text(project.name)
                            if task.dueDate != nil { Text(verbatim: "·") }
                        }
                        if let dueDate = task.dueDate {
                            Text(dueDate.formatted(.dateTime.day().month()))
                                .foregroundStyle(task.isOverdue ? .red : .secondary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var welcomeHintRow: some View {
        Label {
            Text("Capture your first photo to start your activity feed")
        } icon: {
            Image(systemName: "camera.viewfinder")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private var noRecentActivityRow: some View {
        Label {
            Text("No activity in the last 7 days")
        } icon: {
            Image(systemName: "calendar")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private var createProjectCTA: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text("No projects yet")
                .font(.headline)
            Text("Create a project for each job site to keep photos organized.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                isShowingCreateProject = true
            } label: {
                // Explicit HStack rather than `Label`: inside a `List` row the
                // default label style can drop the icon glyph while keeping its
                // reserved width, leaving a blank gap before the title.
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("New Project")
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
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

    // MARK: - Trial banner

    /// Shown only for the owner during their own org's trial (`showsTrialBanner`).
    /// Taps open Plan & Billing so they can subscribe before the trial ends.
    private var trialBanner: some View {
        Button {
            isShowingPlans = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("^[\(session.trialDaysRemaining) day](inflect: true) left in your free trial")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Choose a plan to keep every feature")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
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
            // A user owns at most one org; once they do, the create entry is hidden.
            if !session.ownsOrganization {
                Button {
                    isShowingCreateOrg = true
                } label: {
                    Label("Create Organization", systemImage: "plus")
                }
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
