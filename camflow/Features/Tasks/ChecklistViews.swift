import SwiftUI
import SwiftData

/// Creates a checklist for a project — blank or from a template.
struct ChecklistEditorSheet: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @Query(filter: #Predicate<ChecklistTemplate> { $0.deletedAt == nil }, sort: \ChecklistTemplate.name)
    private var templates: [ChecklistTemplate]

    @State private var name = ""
    @State private var templateID: UUID?
    @State private var assigneeID: UUID?

    private var selectedTemplate: ChecklistTemplate? {
        templates.first { $0.id == templateID }
    }

    private var effectiveName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty, let selectedTemplate {
            return selectedTemplate.name
        }
        return trimmed
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Checklist name", text: $name, prompt: Text(selectedTemplate?.name ?? String(localized: "Checklist name")))
                }

                if !templates.isEmpty {
                    Section {
                        Picker("Template", selection: $templateID) {
                            Text("Blank").tag(UUID?.none)
                            ForEach(templates) { template in
                                Text("\(template.name) (\(template.itemTitles.count))").tag(Optional(template.id))
                            }
                        }
                    } footer: {
                        Text("Manage templates under More → Checklist Templates.")
                    }
                }

                Section {
                    AssigneePicker(project: project, selectedID: $assigneeID)
                }
            }
            .navigationTitle("New Checklist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(effectiveName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func create() {
        let assignee = AssigneePicker.candidates(for: project, context: modelContext)
            .first { $0.id == assigneeID }
        let checklist = ChecklistStore(context: modelContext).create(
            name: effectiveName,
            template: selectedTemplate,
            assignee: assignee,
            project: project
        )
        if let assignee {
            NotificationStore(context: modelContext)
                .notifyChecklistAssigned(checklist, assignee: assignee, by: session.activeMembership)
        }
        dismiss()
    }
}

/// Checklist detail: check items off (auto-timestamped), attach proof
/// photos per item, add items, reassign.
struct ChecklistDetailView: View {
    @Bindable var checklist: Checklist

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @State private var newItemTitle = ""
    @State private var photoPickerItem: ChecklistItem?
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isConfirmingDelete = false
    @State private var assigneeID: UUID?

    private var items: [ChecklistItem] {
        checklist.sortedItems
    }

    /// Checking items off and attaching proof photos is open to the assignee
    /// and privileged roles; structural changes (add/delete items, rename,
    /// delete, reassign) require `.manageTasks`.
    private var canAct: Bool { session.canModify(checklist) }
    private var canManage: Bool { session.can(.manageTasks) }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    ProgressView(value: checklist.progress)
                        .tint(checklist.progress == 1 ? .green : .accentColor)
                    Text("\(items.filter(\.isDone).count)/\(items.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if let project = checklist.project, canManage {
                    AssigneePicker(project: project, selectedID: $assigneeID)
                        .onChange(of: assigneeID) {
                            let store = ChecklistStore(context: modelContext)
                            let previousAssigneeID = checklist.assignee?.id
                            let newAssignee = AssigneePicker.candidates(for: project, context: modelContext)
                                .first { $0.id == assigneeID }
                            checklist.assignee = newAssignee
                            store.touch(checklist)
                            if let newAssignee, newAssignee.id != previousAssigneeID {
                                NotificationStore(context: modelContext)
                                    .notifyChecklistAssigned(checklist, assignee: newAssignee, by: session.activeMembership)
                            }
                        }
                } else if let assignee = checklist.assignee, assignee.deletedAt == nil {
                    HStack {
                        Text("Assignee")
                        Spacer()
                        MemberAvatar(member: assignee, size: 24)
                        Text(assignee.name)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Items") {
                ForEach(items) { item in
                    checklistItemRow(item)
                }
                .onDelete { offsets in
                    let store = ChecklistStore(context: modelContext)
                    for offset in offsets {
                        store.softDeleteItem(items[offset])
                    }
                }
                .deleteDisabled(!canManage)

                if canManage {
                    HStack {
                        TextField("Add item", text: $newItemTitle)
                            .onSubmit(addItem)
                        Button {
                            addItem()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newItemTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .navigationTitle(checklist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            renameText = checklist.name
                            isRenaming = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Delete Checklist", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(item: $photoPickerItem) { item in
            if let project = checklist.project {
                ProjectPhotoPickerSheet(project: project, singleSelection: true) { photos in
                    item.photoID = photos.first?.id
                    item.updatedAt = .now
                    ChecklistStore(context: modelContext).touch(checklist)
                }
            }
        }
        .alert("Rename Checklist", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    checklist.name = trimmed
                    ChecklistStore(context: modelContext).touch(checklist)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this checklist?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                ChecklistStore(context: modelContext).softDelete(checklist)
                dismiss()
            }
        }
        .onAppear {
            assigneeID = checklist.assignee?.id
        }
    }

    private func checklistItemRow(_ item: ChecklistItem) -> some View {
        HStack(spacing: 12) {
            Button {
                ChecklistStore(context: modelContext).toggleItem(item)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canAct)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
                if let completedAt = item.completedAt {
                    Text(completedAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let photoID = item.photoID,
               let photo = checklist.project?.activePhotos.first(where: { $0.id == photoID }) {
                NavigationLink(value: photo) {
                    PhotoCell(photo: photo)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if canAct {
                        Button(role: .destructive) {
                            item.photoID = nil
                            item.updatedAt = .now
                            ChecklistStore(context: modelContext).touch(checklist)
                        } label: {
                            Label("Remove Photo", systemImage: "minus.circle")
                        }
                    }
                }
            } else if canAct {
                Button {
                    photoPickerItem = item
                } label: {
                    Image(systemName: "photo.badge.plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func addItem() {
        let title = newItemTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        ChecklistStore(context: modelContext).addItem(to: checklist, title: title)
        newItemTitle = ""
    }
}
