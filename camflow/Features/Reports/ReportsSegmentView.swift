import SwiftUI
import SwiftData

/// Reports segment of project detail: report history + builder entry point.
struct ReportsSegmentView: View {
    @Bindable var project: Project

    @Environment(\.modelContext) private var modelContext

    @State private var isShowingBuilder = false
    @State private var previewingReport: Report?

    private var reports: [Report] {
        project.reports
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if reports.isEmpty {
                ContentUnavailableView {
                    Label("No Reports Yet", systemImage: "doc.richtext")
                } description: {
                    Text("Build professional PDF reports from this project's photos.")
                } actions: {
                    Button("New Report") { isShowingBuilder = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(project.activePhotos.isEmpty)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(reports) { report in
                        Button {
                            previewingReport = report
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(report.title)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 8) {
                                    Text(report.createdAt, format: .dateTime.day().month().year())
                                    Text(verbatim: "·")
                                    Text("^[\(report.photoIDs.count) photo](inflect: true)")
                                    if report.includesChecklistSummary {
                                        Text(verbatim: "·")
                                        Label("Checklists", systemImage: "checklist")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let store = ReportStore(context: modelContext)
                        for offset in offsets {
                            store.softDelete(reports[offset])
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingBuilder = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(project.activePhotos.isEmpty)
            }
        }
        .fullScreenCover(isPresented: $isShowingBuilder) {
            ReportBuilderView(project: project)
        }
        .sheet(item: $previewingReport) { report in
            ReportPreviewSheet(report: report, project: project)
        }
    }
}

/// Opens a generated report PDF with share; regenerates if the file is gone.
struct ReportPreviewSheet: View {
    let report: Report
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @State private var pdfURL: URL?
    @State private var isRegenerating = false

    var body: some View {
        NavigationStack {
            Group {
                if let pdfURL {
                    PDFKitView(url: pdfURL)
                        .ignoresSafeArea(edges: .bottom)
                } else if isRegenerating {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Generating PDF…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView {
                        Label("PDF Missing", systemImage: "doc.questionmark")
                    } description: {
                        Text("The PDF file is no longer on disk.")
                    } actions: {
                        Button("Regenerate") {
                            Task { await regenerate() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(report.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if let pdfURL {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: pdfURL)
                    }
                }
            }
            .onAppear(perform: locatePDF)
        }
    }

    private func locatePDF() {
        guard let fileName = report.pdfFileName else { return }
        let url = FileStorage.url(for: fileName, in: .reports)
        if FileManager.default.fileExists(atPath: url.path) {
            pdfURL = url
        }
    }

    private func regenerate() async {
        isRegenerating = true
        defer { isRegenerating = false }
        if let url = await ReportPDFRenderer.render(report: report, project: project, organization: session.activeOrganization) {
            report.pdfFileName = url.lastPathComponent
            ReportStore(context: modelContext).touch(report)
            pdfURL = url
        }
    }
}
