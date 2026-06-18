import SwiftUI
import SwiftData

/// Pages sub-tab of the Docs segment: page history + "New Page" entry point.
/// Mirrors `ReportsSegmentView`.
struct PagesSegmentView: View {
    @Bindable var project: Project

    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @State private var isChoosingTemplate = false
    @State private var editingPage: Page?
    @State private var upgradeContext: UpgradeContext?

    private var pages: [Page] {
        project.activePages.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        Group {
            if pages.isEmpty {
                ContentUnavailableView {
                    Label("No Pages Yet", systemImage: "doc.text.image")
                } description: {
                    Text("Build rich notes — daily logs, photo reports, and site inspections — from this project's photos and text.")
                } actions: {
                    Button("New Page") { startNewPage() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(pages) { page in
                        Button {
                            editingPage = page
                        } label: {
                            pageRow(page)
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        let store = PageStore(context: modelContext)
                        for offset in offsets {
                            store.softDelete(pages[offset])
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    startNewPage()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isChoosingTemplate) {
            PageTemplateChooser { template in
                let page = PageStore(context: modelContext).create(
                    title: template.defaultPageTitle,
                    document: template.document(),
                    project: project,
                    author: session.activeMembership
                )
                editingPage = page
            }
        }
        .fullScreenCover(item: $editingPage) { page in
            PageEditorView(page: page, project: project)
        }
        .sheet(item: $upgradeContext) { UpgradePromptSheet(context: $0) }
    }

    /// Pages are a Pro feature; on Basic the create action presents the upsell.
    /// Existing pages stay viewable and editable (downgrade rule).
    private func startNewPage() {
        if session.activePlan.includesPages {
            isChoosingTemplate = true
        } else {
            upgradeContext = .pages
        }
    }

    private func pageRow(_ page: Page) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(page.title.isEmpty ? "Untitled Page" : page.title)
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                Text(page.updatedAt, format: .dateTime.day().month().year())
                let photoCount = photoCount(in: page)
                if photoCount > 0 {
                    Text(verbatim: "·")
                    Text("^[\(photoCount) photo](inflect: true)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func photoCount(in page: Page) -> Int {
        page.document.blocks.reduce(0) { $0 + ($1.photoIDs?.count ?? 0) }
    }
}

/// "New Page" template picker — built-in starter layouts.
struct PageTemplateChooser: View {
    let onPick: (PageTemplate) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(PageTemplate.allCases) { template in
                Button {
                    onPick(template)
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: template.systemImage)
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title)
                                .foregroundStyle(.primary)
                            Text(template.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("New Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
