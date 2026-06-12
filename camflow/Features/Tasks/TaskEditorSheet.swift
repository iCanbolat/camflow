import SwiftUI
import SwiftData

/// Create or edit a task: title, note, due date, assignee.
struct TaskEditorSheet: View {
    let project: Project
    let task: ProjectTask?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var note = ""
    @State private var hasDueDate = false
    @State private var dueDate = Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
    @State private var assigneeID: UUID?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task title", text: $title)
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Toggle("Due date", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }

                Section {
                    AssigneePicker(project: project, selectedID: $assigneeID)
                }
            }
            .navigationTitle(task == nil ? "New Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private func loadExisting() {
        guard let task else { return }
        title = task.title
        note = task.note
        if let existingDue = task.dueDate {
            hasDueDate = true
            dueDate = existingDue
        }
        assigneeID = task.assignee?.id
    }

    private func save() {
        let store = TaskStore(context: modelContext)
        let assignee = AssigneePicker.candidates(for: project, context: modelContext)
            .first { $0.id == assigneeID }

        if let task {
            task.title = trimmedTitle
            task.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            task.dueDate = hasDueDate ? dueDate : nil
            task.assignee = assignee
            store.touch(task)
        } else {
            store.create(
                title: trimmedTitle,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                dueDate: hasDueDate ? dueDate : nil,
                assignee: assignee,
                project: project
            )
        }
        dismiss()
    }
}

/// Picks a responsible member from the project's team (plus the owner).
struct AssigneePicker: View {
    let project: Project
    @Binding var selectedID: UUID?

    @Environment(\.modelContext) private var modelContext

    private var candidates: [OrgMember] {
        Self.candidates(for: project, context: modelContext)
    }

    var body: some View {
        Picker("Assignee", selection: $selectedID) {
            Text("Unassigned").tag(UUID?.none)
            ForEach(candidates) { member in
                Text(member.name).tag(Optional(member.id))
            }
        }
    }

    /// The owning org's owner + this project's members, deduplicated.
    @MainActor
    static func candidates(for project: Project, context: ModelContext) -> [OrgMember] {
        let owner = project.organization?.activeMembers.first { $0.role == .owner }
        var result: [OrgMember] = []
        if let owner { result.append(owner) }
        for member in project.activeMembers where member.id != owner?.id {
            result.append(member)
        }
        return result
    }
}
