import SwiftUI
import SwiftData

/// Block editor for a `Page`. Edits a local working copy of the block document
/// and autosaves (debounced + on dismiss) through `PageStore`.
struct PageEditorView: View {
    @Bindable var page: Page
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @State private var title: String
    @State private var blocks: [PageBlock]
    @State private var saveTask: Task<Void, Never>?
    @State private var isExporting = false
    @State private var exported: ExportedPDF?

    init(page: Page, project: Project) {
        self.page = page
        self.project = project
        _title = State(initialValue: page.title)
        _blocks = State(initialValue: page.document.blocks)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Page title", text: $title)
                        .font(.title2.weight(.bold))
                        .textInputAutocapitalization(.words)

                    ForEach($blocks) { $block in
                        PageBlockEditor(
                            block: $block,
                            project: project,
                            onMoveUp: { move(block.id, by: -1) },
                            onMoveDown: { move(block.id, by: 1) },
                            onDelete: { delete(block.id) }
                        )
                        Divider().opacity(block.kind == .divider ? 0 : 0.4)
                    }

                    addBlockMenu
                        .padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle("Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportPDF()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(isExporting)
                }
            }
            .overlay {
                if isExporting {
                    ProgressView("Generating PDF…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .sheet(item: $exported) { item in
                PagePDFPreviewSheet(url: item.url, title: title)
            }
            .onChange(of: blocks) { scheduleSave() }
            .onChange(of: title) { scheduleSave() }
            .onDisappear {
                saveTask?.cancel()
                save()
            }
        }
    }

    private var addBlockMenu: some View {
        Menu {
            Button { add(.heading) } label: { Label("Heading", systemImage: "textformat.size") }
            Button { add(.paragraph) } label: { Label("Text", systemImage: "text.alignleft") }
            Button { add(.bulletList) } label: { Label("Bulleted List", systemImage: "list.bullet") }
            Button { add(.numberedList) } label: { Label("Numbered List", systemImage: "list.number") }
            Button { add(.checklist) } label: { Label("Checklist", systemImage: "checklist") }
            Button { add(.photo) } label: { Label("Photo", systemImage: "photo") }
            Button { add(.photoGrid) } label: { Label("Photo Grid", systemImage: "square.grid.2x2") }
            Divider()
            Button { add(.divider) } label: { Label("Divider", systemImage: "minus") }
        } label: {
            Label("Add Block", systemImage: "plus.circle.fill")
                .font(.headline)
        }
    }

    // MARK: - Block mutations

    private func add(_ kind: PageBlock.Kind) {
        blocks.append(.make(kind))
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard blocks.indices.contains(target) else { return }
        blocks.swapAt(index, target)
    }

    private func delete(_ id: UUID) {
        blocks.removeAll { $0.id == id }
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        PageStore(context: modelContext).update(
            page,
            title: title,
            document: PageDocument(blocks: blocks)
        )
    }

    // MARK: - Export

    private func exportPDF() {
        isExporting = true
        Task {
            save()
            let url = await PagePDFRenderer.render(
                page: page,
                project: project,
                organization: session.activeOrganization
            )
            if let url {
                page.pdfFileName = url.lastPathComponent
                PageStore(context: modelContext).touch(page)
            }
            isExporting = false
            if let url {
                exported = ExportedPDF(url: url)
            }
        }
    }

    private struct ExportedPDF: Identifiable {
        let id = UUID()
        let url: URL
    }
}

/// PDF preview + share for an exported page. Reuses `PDFKitView` (defined in
/// `ReportBuilderView.swift`), mirroring `ReportPreviewSheet`.
struct PagePDFPreviewSheet: View {
    let url: URL
    let title: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title.isEmpty ? "Page" : title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url)
                    }
                }
        }
    }
}
