import SwiftUI
import SwiftData

/// The Tasks segment of project detail: tasks + checklists with their own
/// add menu, rows, and navigation destinations.
struct TasksSegmentView: View {
    @Bindable var project: Project

    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @State private var isShowingTaskEditor = false
    @State private var isShowingChecklistEditor = false
    @State private var upgradeContext: UpgradeContext?

    /// Owner/admin/manager create and manage tasks and checklists; standard
    /// members only act on work assigned to them.
    private var canManage: Bool { session.can(.manageTasks) }

    private var tasks: [ProjectTask] {
        project.tasks
            .filter { $0.deletedAt == nil }
            .sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted {
                    return !lhs.isCompleted
                }
                let lhsDue = lhs.dueDate ?? .distantFuture
                let rhsDue = rhs.dueDate ?? .distantFuture
                if lhsDue != rhsDue {
                    return lhsDue < rhsDue
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private var checklists: [Checklist] {
        project.checklists
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if tasks.isEmpty && checklists.isEmpty {
                ContentUnavailableView {
                    Label("No Tasks Yet", systemImage: "checklist")
                } description: {
                    Text(canManage
                         ? "Track work with tasks and checklists, assign them to your team."
                         : "Tasks and checklists assigned to you will appear here.")
                } actions: {
                    if canManage {
                        HStack {
                            Button("New Task") { startNewTask() }
                                .buttonStyle(.borderedProminent)
                            Button("New Checklist") { startNewChecklist() }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    if !tasks.isEmpty {
                        Section("Tasks") {
                            ForEach(tasks) { task in
                                NavigationLink(value: task) {
                                    TaskRow(task: task)
                                }
                            }
                            .onDelete { offsets in
                                let store = TaskStore(context: modelContext)
                                for offset in offsets {
                                    store.softDelete(tasks[offset])
                                }
                            }
                            .deleteDisabled(!canManage)
                        }
                    }

                    if !checklists.isEmpty {
                        Section("Checklists") {
                            ForEach(checklists) { checklist in
                                NavigationLink(value: checklist) {
                                    ChecklistRow(checklist: checklist)
                                }
                            }
                            .onDelete { offsets in
                                let store = ChecklistStore(context: modelContext)
                                for offset in offsets {
                                    store.softDelete(checklists[offset])
                                }
                            }
                            .deleteDisabled(!canManage)
                        }
                    }
                }
            }
        }
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            startNewTask()
                        } label: {
                            Label("New Task", systemImage: "checkmark.circle")
                        }
                        Button {
                            startNewChecklist()
                        } label: {
                            Label("New Checklist", systemImage: "list.bullet.rectangle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingTaskEditor) {
            TaskEditorSheet(project: project, task: nil)
        }
        .sheet(isPresented: $isShowingChecklistEditor) {
            ChecklistEditorSheet(project: project)
        }
        .sheet(item: $upgradeContext) { UpgradePromptSheet(context: $0) }
        .navigationDestination(for: ProjectTask.self) { task in
            TaskDetailView(task: task)
        }
        .navigationDestination(for: Checklist.self) { checklist in
            ChecklistDetailView(checklist: checklist)
        }
    }

    /// Tasks are a Pro feature; on Basic the create action presents the upsell.
    /// Existing tasks stay viewable and editable (downgrade rule).
    private func startNewTask() {
        if session.activePlan.includesTasks {
            isShowingTaskEditor = true
        } else {
            upgradeContext = .tasks
        }
    }

    /// Checklists are a Pro feature; on Basic the create action presents the upsell.
    private func startNewChecklist() {
        if session.activePlan.includesChecklists {
            isShowingChecklistEditor = true
        } else {
            upgradeContext = .checklists
        }
    }
}

struct TaskRow: View {
    let task: ProjectTask

    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    private var canToggle: Bool { session.canModify(task) }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                TaskStore(context: modelContext).toggleCompletion(task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canToggle)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)

                HStack(spacing: 10) {
                    if let dueDate = task.dueDate {
                        Label(dueDate.formatted(.dateTime.day().month()), systemImage: "calendar")
                            .foregroundStyle(task.isOverdue ? .red : .secondary)
                    }
                    if let completedAt = task.completedAt {
                        Label(completedAt.formatted(.dateTime.day().month().hour().minute()), systemImage: "checkmark")
                            .foregroundStyle(.green)
                    }
                    if !task.activeComments.isEmpty {
                        Label("\(task.activeComments.count)", systemImage: "bubble.left")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }

            Spacer()

            if let assignee = task.assignee, assignee.deletedAt == nil {
                MemberAvatar(member: assignee, size: 28)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ChecklistRow: View {
    let checklist: Checklist

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(checklist.name)
                Spacer()
                if let assignee = checklist.assignee, assignee.deletedAt == nil {
                    MemberAvatar(member: assignee, size: 28)
                }
            }

            HStack(spacing: 8) {
                ProgressView(value: checklist.progress)
                    .tint(checklist.progress == 1 ? .green : .accentColor)
                Text("\(checklist.sortedItems.filter(\.isDone).count)/\(checklist.sortedItems.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}
