import SwiftUI
import SwiftData

/// The Tasks segment of project detail: tasks + checklists with their own
/// add menu, rows, and navigation destinations.
struct TasksSegmentView: View {
    @Bindable var project: Project

    @Environment(\.modelContext) private var modelContext

    @State private var isShowingTaskEditor = false
    @State private var isShowingChecklistEditor = false

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
                    Text("Track work with tasks and checklists, assign them to your team.")
                } actions: {
                    HStack {
                        Button("New Task") { isShowingTaskEditor = true }
                            .buttonStyle(.borderedProminent)
                        Button("New Checklist") { isShowingChecklistEditor = true }
                            .buttonStyle(.bordered)
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
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isShowingTaskEditor = true
                    } label: {
                        Label("New Task", systemImage: "checkmark.circle")
                    }
                    Button {
                        isShowingChecklistEditor = true
                    } label: {
                        Label("New Checklist", systemImage: "list.bullet.rectangle")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingTaskEditor) {
            TaskEditorSheet(project: project, task: nil)
        }
        .sheet(isPresented: $isShowingChecklistEditor) {
            ChecklistEditorSheet(project: project)
        }
        .navigationDestination(for: ProjectTask.self) { task in
            TaskDetailView(task: task)
        }
        .navigationDestination(for: Checklist.self) { checklist in
            ChecklistDetailView(checklist: checklist)
        }
    }
}

struct TaskRow: View {
    let task: ProjectTask

    @Environment(\.modelContext) private var modelContext

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
