import SwiftUI
import SwiftData
import PDFKit

/// Three-step report wizard: select photos → arrange + notes → preview & share.
struct ReportBuilderView: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    private enum Step: Int {
        case select = 1
        case arrange = 2
        case export = 3
    }

    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var tags: [Tag]

    @State private var step: Step = .select

    // Step 1
    @State private var selectedIDs: Set<UUID> = []
    @State private var filterTagID: UUID?

    // Step 2
    @State private var orderedPhotos: [Photo] = []
    @State private var photoNotes: [UUID: String] = [:]
    @State private var layout: Report.Layout = .twoPerPage

    // Step 3
    @State private var title = ""
    @State private var includeChecklists = false
    @State private var isGenerating = false
    @State private var pdfURL: URL?

    private var hasChecklists: Bool {
        project.checklists.contains { $0.deletedAt == nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .select:
                    selectStep
                case .arrange:
                    arrangeStep
                case .export:
                    exportStep
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                navigationBar
            }
        }
        .interactiveDismissDisabled(pdfURL != nil)
        .onAppear {
            title = defaultTitle
            includeChecklists = hasChecklists
        }
    }

    private var stepTitle: LocalizedStringKey {
        switch step {
        case .select: "Select Photos"
        case .arrange: "Arrange"
        case .export: "Export Report"
        }
    }

    private var defaultTitle: String {
        "\(project.name) — \(Date.now.formatted(date: .abbreviated, time: .omitted))"
    }

    // MARK: - Step 1: Select

    private var availablePhotos: [Photo] {
        // Reports are photo-only; videos can't be rendered into PDF pages.
        var photos = project.activePhotos.filter { !$0.isVideo }.sorted { $0.capturedAt > $1.capturedAt }
        if let filterTagID {
            photos = photos.filter { photo in photo.tags.contains { $0.id == filterTagID } }
        }
        return photos
    }

    private var selectStep: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                ForEach(availablePhotos) { photo in
                    PhotoCell(photo: photo, showAuthor: false)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: selectedIDs.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .tint)
                                .shadow(radius: 2)
                                .padding(6)
                        }
                        .opacity(selectedIDs.contains(photo.id) ? 0.7 : 1)
                        .onTapGesture {
                            if selectedIDs.contains(photo.id) {
                                selectedIDs.remove(photo.id)
                            } else {
                                selectedIDs.insert(photo.id)
                            }
                        }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !tags.isEmpty {
                    Menu {
                        Picker("Filter by tag", selection: $filterTagID) {
                            Text("All Photos").tag(UUID?.none)
                            ForEach(tags) { tag in
                                Text(tag.name).tag(Optional(tag.id))
                            }
                        }
                    } label: {
                        Image(systemName: filterTagID == nil ? "tag" : "tag.fill")
                    }
                }
                Button(selectedIDs.count == availablePhotos.count ? "None" : "All") {
                    if selectedIDs.count == availablePhotos.count {
                        selectedIDs.removeAll()
                    } else {
                        selectedIDs = Set(availablePhotos.map(\.id))
                    }
                }
            }
        }
    }

    // MARK: - Step 2: Arrange

    private var arrangeStep: some View {
        List {
            Section {
                Picker("Layout", selection: $layout) {
                    Text("1 / page").tag(Report.Layout.onePerPage)
                    Text("2 / page").tag(Report.Layout.twoPerPage)
                    Text("4 / page").tag(Report.Layout.fourPerPage)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Page Layout")
            }

            Section {
                ForEach(orderedPhotos) { photo in
                    HStack(spacing: 12) {
                        PhotoCell(photo: photo)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        TextField("Add note", text: noteBinding(for: photo.id), axis: .vertical)
                            .lineLimit(1...3)
                            .font(.callout)
                    }
                }
                .onMove { source, destination in
                    orderedPhotos.move(fromOffsets: source, toOffset: destination)
                }
            } header: {
                Text("Drag to reorder · ^[\(orderedPhotos.count) photo](inflect: true)")
            }
        }
        .environment(\.editMode, .constant(.active))
    }

    private func noteBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { photoNotes[id] ?? "" },
            set: { photoNotes[id] = $0 }
        )
    }

    // MARK: - Step 3: Export

    private var exportStep: some View {
        Form {
            Section("Title") {
                TextField("Report title", text: $title)
            }

            Section {
                LabeledContent("Photos", value: "\(orderedPhotos.count)")
                LabeledContent("Layout") {
                    switch layout {
                    case .onePerPage: Text("1 photo per page")
                    case .twoPerPage: Text("2 photos per page")
                    case .fourPerPage: Text("4 photos per page")
                    }
                }
                if hasChecklists {
                    Toggle("Include checklist summary", isOn: $includeChecklists)
                }
            }

            Section {
                if isGenerating {
                    HStack {
                        ProgressView()
                        Text("Generating PDF…")
                            .foregroundStyle(.secondary)
                    }
                } else if let pdfURL {
                    PDFKitView(url: pdfURL)
                        .frame(height: 420)
                        .listRowInsets(EdgeInsets())

                    ShareLink(item: pdfURL) {
                        Label("Share PDF", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Button {
                        Task { await generate() }
                    } label: {
                        Label("Generate PDF", systemImage: "doc.richtext")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }

        let report = ReportStore(context: modelContext).create(
            title: title.trimmingCharacters(in: .whitespaces),
            photoIDs: orderedPhotos.map(\.id),
            photoNotes: photoNotes.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty },
            layout: layout,
            includesChecklistSummary: includeChecklists,
            project: project
        )

        if let url = await ReportPDFRenderer.render(report: report, project: project, organization: session.activeOrganization) {
            report.pdfFileName = url.lastPathComponent
            ReportStore(context: modelContext).touch(report)
            pdfURL = url
        }
    }

    // MARK: - Wizard navigation

    private var navigationBar: some View {
        HStack {
            if step != .select && pdfURL == nil {
                Button {
                    step = Step(rawValue: step.rawValue - 1) ?? .select
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }

            Spacer()

            Text("Step \(step.rawValue) / 3")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            switch step {
            case .select:
                Button("Next") {
                    orderedPhotos = availablePhotos.filter { selectedIDs.contains($0.id) }
                    step = .arrange
                }
                .fontWeight(.semibold)
                .disabled(selectedIDs.isEmpty)
            case .arrange:
                Button("Next") {
                    step = .export
                }
                .fontWeight(.semibold)
            case .export:
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
                    .disabled(pdfURL == nil && !isGenerating)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

/// PDFKit preview wrapper.
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
