import SwiftUI
import SwiftData

/// CRUD for photo tags.
struct TagManagerView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var tags: [Tag]

    @State private var editingTag: Tag?
    @State private var isAddingTag = false

    var body: some View {
        Group {
            if tags.isEmpty {
                ContentUnavailableView {
                    Label("No Tags Yet", systemImage: "tag")
                } description: {
                    Text("Tags categorize photos within and across projects — like “Electrical” or “Damage”.")
                } actions: {
                    Button("New Tag") { isAddingTag = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(tags) { tag in
                        Button {
                            editingTag = tag
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(hex: tag.colorHex))
                                    .frame(width: 14, height: 14)
                                Text(tag.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("^[\(tag.photos.count) photo](inflect: true)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            let tag = tags[offset]
                            tag.deletedAt = .now
                            tag.updatedAt = .now
                        }
                    }
                }
            }
        }
        .navigationTitle("Photo Tags")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingTag = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingTag) {
            NameColorEditorSheet(title: "New Tag") { name, colorHex in
                modelContext.insert(Tag(name: name, colorHex: colorHex))
            }
        }
        .sheet(item: $editingTag) { tag in
            NameColorEditorSheet(title: "Edit Tag", name: tag.name, colorHex: tag.colorHex) { name, colorHex in
                tag.name = name
                tag.colorHex = colorHex
                tag.updatedAt = .now
            }
        }
    }
}

/// CRUD for project status labels.
struct LabelManagerView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<ProjectLabel> { $0.deletedAt == nil }, sort: \ProjectLabel.sortOrder)
    private var labels: [ProjectLabel]

    @State private var editingLabel: ProjectLabel?
    @State private var isAddingLabel = false

    var body: some View {
        List {
            ForEach(labels) { label in
                Button {
                    editingLabel = label
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(hex: label.colorHex))
                            .frame(width: 14, height: 14)
                        Text(label.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("^[\(label.projects.count) project](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                for offset in offsets {
                    let label = labels[offset]
                    label.deletedAt = .now
                    label.updatedAt = .now
                }
            }
        }
        .navigationTitle("Project Labels")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingLabel = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingLabel) {
            NameColorEditorSheet(title: "New Label") { name, colorHex in
                let nextOrder = (labels.map(\.sortOrder).max() ?? -1) + 1
                modelContext.insert(ProjectLabel(name: name, colorHex: colorHex, sortOrder: nextOrder))
            }
        }
        .sheet(item: $editingLabel) { label in
            NameColorEditorSheet(title: "Edit Label", name: label.name, colorHex: label.colorHex) { name, colorHex in
                label.name = name
                label.colorHex = colorHex
                label.updatedAt = .now
            }
        }
    }
}

/// Shared name + color sheet for tags and labels.
struct NameColorEditorSheet: View {
    let title: LocalizedStringKey
    var name: String = ""
    var colorHex: String = TagPalette.colors[0]
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editedName = ""
    @State private var editedColorHex = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $editedName)
                Section("Color") {
                    ColorSwatchPicker(selectedHex: $editedColorHex)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(editedName.trimmingCharacters(in: .whitespaces), editedColorHex)
                        dismiss()
                    }
                    .disabled(editedName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                editedName = name
                editedColorHex = colorHex
            }
        }
        .presentationDetents([.medium])
    }
}
