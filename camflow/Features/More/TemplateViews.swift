import SwiftUI
import SwiftData

/// Reusable checklist templates (e.g. "Roof Inspection") managed from More.
struct TemplateListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<ChecklistTemplate> { $0.deletedAt == nil }, sort: \ChecklistTemplate.name)
    private var templates: [ChecklistTemplate]

    @State private var isAddingTemplate = false
    @State private var editingTemplate: ChecklistTemplate?

    var body: some View {
        Group {
            if templates.isEmpty {
                ContentUnavailableView {
                    Label("No Templates Yet", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Build reusable checklists like “Roof Inspection” or “Final Walkthrough”.")
                } actions: {
                    Button("New Template") { isAddingTemplate = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(templates) { template in
                        Button {
                            editingTemplate = template
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .foregroundStyle(.primary)
                                Text("^[\(template.itemTitles.count) item](inflect: true)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let store = ChecklistStore(context: modelContext)
                        for offset in offsets {
                            store.softDeleteTemplate(templates[offset])
                        }
                    }
                }
            }
        }
        .navigationTitle("Checklist Templates")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingTemplate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingTemplate) {
            TemplateEditorSheet(template: nil)
        }
        .sheet(item: $editingTemplate) { template in
            TemplateEditorSheet(template: template)
        }
    }
}

struct TemplateEditorSheet: View {
    let template: ChecklistTemplate?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var items: [String] = []
    @State private var newItemTitle = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Template name", text: $name)
                }

                Section("Items") {
                    ForEach(items.indices, id: \.self) { index in
                        Text(items[index])
                    }
                    .onDelete { offsets in
                        items.remove(atOffsets: offsets)
                    }
                    .onMove { source, destination in
                        items.move(fromOffsets: source, toOffset: destination)
                    }

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
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty || items.isEmpty)
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private func loadExisting() {
        guard let template else { return }
        name = template.name
        items = template.itemTitles
    }

    private func addItem() {
        let title = newItemTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        items.append(title)
        newItemTitle = ""
    }

    private func save() {
        let store = ChecklistStore(context: modelContext)
        if let template {
            template.name = trimmedName
            template.itemTitles = items
            store.touchTemplate(template)
        } else {
            store.createTemplate(name: trimmedName, itemTitles: items)
        }
        dismiss()
    }
}
