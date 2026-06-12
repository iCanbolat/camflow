import SwiftUI
import SwiftData

/// Renders a report into a multi-page A4 PDF: cover page, photo pages
/// (annotations baked via the shared AnnotationRenderer), and an optional
/// checklist summary. Pages are SwiftUI views drawn vector-sharp through
/// ImageRenderer into a CGContext PDF.
@MainActor
enum ReportPDFRenderer {
    static let pageSize = CGSize(width: 595, height: 842) // A4 portrait, points

    struct PhotoEntry: Identifiable {
        let id: UUID
        let image: UIImage
        let shapes: [AnnotationShape]
        let capturedAt: Date
        let latitude: Double?
        let longitude: Double?
        let note: String
    }

    struct ChecklistEntry: Identifiable {
        let id: UUID
        let checklistName: String
        let itemTitle: String
        let isDone: Bool
        let completedAt: Date?
    }

    /// Renders the PDF into `FileStorage.reports` and returns its URL.
    static func render(report: Report, project: Project, organization: Organization?) async -> URL? {
        let photos = report.photoIDs.compactMap { id in
            project.activePhotos.first { $0.id == id }
        }

        // Preload image data off the main actor.
        let loadRequests = photos.map { ($0.id, $0.fileName) }
        let images: [UUID: UIImage] = await Task.detached {
            var result: [UUID: UIImage] = [:]
            for (id, fileName) in loadRequests {
                if let image = FileStorage.load(fileName, in: .photos).flatMap(UIImage.init(data:)) {
                    result[id] = image
                }
            }
            return result
        }.value

        let entries: [PhotoEntry] = photos.compactMap { photo in
            guard let image = images[photo.id] else { return nil }
            return PhotoEntry(
                id: photo.id,
                image: image,
                shapes: AnnotationDocument.decode(photo.annotationData).shapes,
                capturedAt: photo.capturedAt,
                latitude: photo.latitude,
                longitude: photo.longitude,
                note: report.photoNotes[photo.id] ?? ""
            )
        }

        let checklistEntries: [ChecklistEntry] = report.includesChecklistSummary
            ? project.checklists
                .filter { $0.deletedAt == nil }
                .flatMap { checklist in
                    checklist.sortedItems.map { item in
                        ChecklistEntry(
                            id: item.id,
                            checklistName: checklist.name,
                            itemTitle: item.title,
                            isDone: item.isDone,
                            completedAt: item.completedAt
                        )
                    }
                }
            : []

        let logo = organization?.logoFileName.flatMap { FileStorage.loadImage($0, in: .branding) }

        // Assemble pages.
        let photosPerPage: Int
        switch report.layout {
        case .onePerPage: photosPerPage = 1
        case .twoPerPage: photosPerPage = 2
        case .fourPerPage: photosPerPage = 4
        }

        var pages: [AnyView] = [AnyView(ReportCoverPage(
            report: report,
            project: project,
            companyName: organization?.name ?? "",
            logo: logo,
            photoCount: entries.count
        ))]

        let photoChunks = stride(from: 0, to: entries.count, by: photosPerPage).map {
            Array(entries[$0..<min($0 + photosPerPage, entries.count)])
        }
        for chunk in photoChunks {
            pages.append(AnyView(ReportPhotoPage(
                entries: chunk,
                layout: report.layout,
                projectName: project.name
            )))
        }

        let checklistChunks = stride(from: 0, to: checklistEntries.count, by: 22).map {
            Array(checklistEntries[$0..<min($0 + 22, checklistEntries.count)])
        }
        for chunk in checklistChunks {
            pages.append(AnyView(ReportChecklistPage(entries: chunk, projectName: project.name)))
        }

        // Draw the document.
        let fileName = "\(report.id.uuidString).pdf"
        let url = FileStorage.url(for: fileName, in: .reports)
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let pdfContext = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return nil }

        let pageCount = pages.count
        for (index, page) in pages.enumerated() {
            let numbered = page
                .frame(width: pageSize.width, height: pageSize.height)
                .overlay(alignment: .bottom) {
                    ReportPageFooter(
                        companyName: organization?.name ?? "",
                        pageNumber: index + 1,
                        pageCount: pageCount
                    )
                }
                .background(.white)
                .environment(\.colorScheme, .light)

            let renderer = ImageRenderer(content: numbered)
            renderer.proposedSize = ProposedViewSize(pageSize)
            pdfContext.beginPDFPage(nil)
            renderer.render { _, draw in
                draw(pdfContext)
            }
            pdfContext.endPDFPage()
        }
        pdfContext.closePDF()
        return url
    }
}

// MARK: - Pages

private struct ReportCoverPage: View {
    let report: Report
    let project: Project
    let companyName: String
    let logo: UIImage?
    let photoCount: Int

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 120)

            if let logo {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.bottom, 12)
            }

            if !companyName.isEmpty {
                Text(companyName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: "#FF6B35"))
                    .padding(.bottom, 40)
            }

            Text(report.title)
                .font(.system(size: 30, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)

            Rectangle()
                .fill(Color(hex: "#FF6B35"))
                .frame(width: 64, height: 3)
                .padding(.vertical, 20)

            VStack(spacing: 6) {
                Text(project.name)
                    .font(.system(size: 16, weight: .medium))
                if !project.address.isEmpty {
                    Text(project.address)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(spacing: 4) {
                Text(report.createdAt.formatted(date: .long, time: .omitted))
                Text("^[\(photoCount) photo](inflect: true)")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.black)
    }
}

private struct ReportPhotoPage: View {
    let entries: [ReportPDFRenderer.PhotoEntry]
    let layout: Report.Layout
    let projectName: String

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(projectName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if layout == .fourPerPage {
                let rows = stride(from: 0, to: entries.count, by: 2).map {
                    Array(entries[$0..<min($0 + 2, entries.count)])
                }
                ForEach(rows.indices, id: \.self) { rowIndex in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(rows[rowIndex]) { entry in
                            PhotoBlock(entry: entry)
                        }
                        if rows[rowIndex].count == 1 {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                if rows.count == 1 {
                    Color.clear.frame(maxHeight: .infinity)
                }
            } else {
                ForEach(entries) { entry in
                    PhotoBlock(entry: entry)
                        .frame(maxHeight: .infinity)
                }
                if layout == .twoPerPage && entries.count == 1 {
                    Color.clear.frame(maxHeight: .infinity)
                }
            }
        }
        .padding(EdgeInsets(top: 28, leading: 36, bottom: 40, trailing: 36))
    }
}

private struct PhotoBlock: View {
    let entry: ReportPDFRenderer.PhotoEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(uiImage: entry.image)
                .resizable()
                .scaledToFit()
                .overlay {
                    if !entry.shapes.isEmpty {
                        Canvas { context, size in
                            AnnotationRenderer.draw(entry.shapes, in: &context, size: size)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(metadataLine)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)

            if !entry.note.isEmpty {
                Text(entry.note)
                    .font(.system(size: 9))
                    .foregroundStyle(.black)
                    .lineLimit(3)
            }
        }
    }

    private var metadataLine: String {
        var line = entry.capturedAt.formatted(date: .abbreviated, time: .shortened)
        if let lat = entry.latitude, let lon = entry.longitude {
            line += String(format: "  ·  %.4f, %.4f", lat, lon)
        }
        return line
    }
}

private struct ReportChecklistPage: View {
    let entries: [ReportPDFRenderer.ChecklistEntry]
    let projectName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Checklist Summary")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black)
                .padding(.bottom, 2)
            Text(projectName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.bottom, 14)

            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(entry.isDone ? Color(hex: "#2E933C") : .secondary)
                    Text(entry.itemTitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.black)
                    Spacer()
                    Text(entry.checklistName)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    if let completedAt = entry.completedAt {
                        Text(completedAt.formatted(.dateTime.day().month().hour().minute()))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                    } else {
                        Color.clear.frame(width: 80, height: 1)
                    }
                }
                .padding(.vertical, 5)
                Divider()
            }

            Spacer()
        }
        .padding(EdgeInsets(top: 28, leading: 36, bottom: 40, trailing: 36))
    }
}

private struct ReportPageFooter: View {
    let companyName: String
    let pageNumber: Int
    let pageCount: Int

    var body: some View {
        HStack {
            Text(companyName.isEmpty ? "CamFlow" : companyName)
            Spacer()
            Text(verbatim: "\(pageNumber) / \(pageCount)")
        }
        .font(.system(size: 8))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 36)
        .padding(.bottom, 16)
    }
}
