import SwiftUI
import UIKit

/// Renders a `Page` block document into a multi-page A4 PDF: a cover page
/// followed by content pages. Unlike `ReportPDFRenderer` (fixed photos per
/// page), pages mix variable-height blocks, so renderable items are measured
/// with `UIHostingController.sizeThatFits` and **greedily packed** into pages.
/// Pages are drawn vector-sharp via `ImageRenderer` into a `CGContext` PDF.
@MainActor
enum PagePDFRenderer {
    static let pageSize = CGSize(width: 595, height: 842) // A4 portrait, points
    static let insets = EdgeInsets(top: 40, leading: 40, bottom: 48, trailing: 40)
    static let itemSpacing: CGFloat = 10
    static let footerHeight: CGFloat = 24

    static var contentWidth: CGFloat { pageSize.width - insets.leading - insets.trailing }
    static var contentHeight: CGFloat { pageSize.height - insets.top - insets.bottom - footerHeight }

    static func render(page: Page, project: Project, organization: Organization?) async -> URL? {
        let document = page.document

        // Resolve photo bytes + annotations for every photo referenced anywhere.
        let photoIDs = Array(Set(document.blocks.flatMap { $0.photoIDs ?? [] }))
        var shapesByID: [UUID: [AnnotationShape]] = [:]
        var fileNames: [(UUID, String)] = []
        for id in photoIDs {
            guard let photo = project.activePhotos.first(where: { $0.id == id }) else { continue }
            shapesByID[id] = AnnotationDocument.decode(photo.annotationData).shapes
            fileNames.append((id, photo.fileName))
        }
        let images: [UUID: UIImage] = await Task.detached {
            var result: [UUID: UIImage] = [:]
            for (id, fileName) in fileNames {
                if let image = FileStorage.load(fileName, in: .photos).flatMap(UIImage.init(data:)) {
                    result[id] = image
                }
            }
            return result
        }.value

        // Build renderable items (lists/checklists/grids split per row so they
        // paginate cleanly), measure each, and greedily pack into pages.
        let items = document.blocks.flatMap { block in
            renderItems(for: block, images: images, shapes: shapesByID)
        }
        let measured = items.map { Measured(view: $0, height: measure($0)) }

        var pagesOfItems: [[AnyView]] = []
        var current: [AnyView] = []
        var used: CGFloat = 0
        for item in measured {
            let needed = item.height + itemSpacing
            if !current.isEmpty && used + needed > contentHeight {
                pagesOfItems.append(current)
                current = []
                used = 0
            }
            current.append(item.view)
            used += needed
        }
        if !current.isEmpty { pagesOfItems.append(current) }
        if pagesOfItems.isEmpty { pagesOfItems = [[]] }

        let logo = organization?.logoFileName.flatMap { FileStorage.loadImage($0, in: .branding) }
        let companyName = organization?.name ?? ""

        var pages: [AnyView] = [AnyView(PageCoverPage(
            title: page.title,
            project: project,
            companyName: companyName,
            logo: logo,
            createdAt: page.createdAt
        ))]
        for itemViews in pagesOfItems {
            pages.append(AnyView(PageContentPage(items: itemViews)))
        }

        // Draw the document.
        let fileName = "\(page.id.uuidString).pdf"
        let url = FileStorage.url(for: fileName, in: .pages)
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let pdfContext = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return nil }

        let pageCount = pages.count
        for (index, content) in pages.enumerated() {
            let numbered = content
                .frame(width: pageSize.width, height: pageSize.height)
                .overlay(alignment: .bottom) {
                    PageFooter(companyName: companyName, pageNumber: index + 1, pageCount: pageCount)
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

    // MARK: - Item construction

    private struct Measured {
        let view: AnyView
        let height: CGFloat
    }

    /// Measures an item's height at the page content width.
    private static func measure(_ view: AnyView) -> CGFloat {
        let controller = UIHostingController(
            rootView: view
                .frame(width: contentWidth, alignment: .leading)
                .environment(\.colorScheme, .light)
        )
        let size = controller.sizeThatFits(in: CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        return ceil(size.height)
    }

    private static func renderItems(
        for block: PageBlock,
        images: [UUID: UIImage],
        shapes: [UUID: [AnnotationShape]]
    ) -> [AnyView] {
        switch block.kind {
        case .heading:
            guard let text = block.text, !text.characters.isEmpty else { return [] }
            return [AnyView(PDFHeading(text: text, level: block.headingLevel ?? 2))]

        case .paragraph:
            guard let text = block.text, !text.characters.isEmpty else { return [] }
            return [AnyView(PDFParagraph(text: text))]

        case .bulletList, .numberedList:
            let items = block.listItems ?? []
            return items.enumerated().compactMap { index, item in
                guard !item.characters.isEmpty else { return nil }
                let marker = block.kind == .numberedList ? "\(index + 1)." : "•"
                return AnyView(PDFListRow(marker: marker, text: item))
            }

        case .checklist:
            let items = block.checklistItems ?? []
            return items.compactMap { item in
                guard !item.text.isEmpty else { return nil }
                return AnyView(PDFChecklistRow(item: item))
            }

        case .divider:
            return [AnyView(PDFDivider())]

        case .photo:
            guard let id = block.photoIDs?.first, let image = images[id] else { return [] }
            return [AnyView(PDFSinglePhoto(
                image: image,
                shapes: shapes[id] ?? [],
                widthFraction: (block.photoSize ?? .full).widthFraction,
                square: block.squareCrop ?? false,
                caption: block.caption
            ))]

        case .photoGrid:
            let ids = block.photoIDs ?? []
            let cols = max(2, min(3, block.columns ?? 2))
            let spacing: CGFloat = 6
            let side = (contentWidth - spacing * CGFloat(cols - 1)) / CGFloat(cols)

            let entries = ids.compactMap { id in images[id].map { (id, $0, shapes[id] ?? []) } }
            let allRows = stride(from: 0, to: entries.count, by: cols).map {
                Array(entries[$0..<min($0 + cols, entries.count)])
            }
            // Keep the grid together: chunk rows so each grid fits one page
            // rather than splitting individual rows across page breaks.
            let rowsPerPage = max(1, Int((contentHeight + spacing) / (side + spacing)))
            let rowChunks = stride(from: 0, to: allRows.count, by: rowsPerPage).map {
                Array(allRows[$0..<min($0 + rowsPerPage, allRows.count)])
            }

            var views: [AnyView] = rowChunks.map { chunk in
                AnyView(PDFPhotoGrid(rows: chunk, columns: cols, side: side, spacing: spacing))
            }
            if let caption = block.caption, !caption.isEmpty {
                views.append(AnyView(PDFCaption(text: caption)))
            }
            return views
        }
    }
}

// MARK: - Item views

private struct PDFHeading: View {
    let text: AttributedString
    let level: Int

    private var size: CGFloat {
        switch level {
        case 1: return 22
        case 3: return 13
        default: return 17
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PDFParagraph: View {
    let text: AttributedString
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PDFListRow: View {
    let marker: String
    let text: AttributedString
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(marker)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(minWidth: 16, alignment: .trailing)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.black)
            Spacer(minLength: 0)
        }
    }
}

private struct PDFChecklistRow: View {
    let item: PageChecklistItem
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundStyle(item.isDone ? Color(hex: "#2E933C") : .secondary)
            Text(item.text)
                .font(.system(size: 11))
                .foregroundStyle(.black)
            Spacer(minLength: 0)
        }
    }
}

private struct PDFDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.15))
            .frame(height: 1)
            .padding(.vertical, 4)
    }
}

private struct PDFCaption: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PDFSinglePhoto: View {
    let image: UIImage
    let shapes: [AnnotationShape]
    let widthFraction: Double
    let square: Bool
    let caption: String?

    var body: some View {
        let width = PagePDFRenderer.contentWidth * widthFraction
        let aspect = image.size.width > 0 ? image.size.height / image.size.width : 0.75
        let height = square ? width : min(width * aspect, PagePDFRenderer.contentHeight * 0.85)

        VStack(alignment: .leading, spacing: 4) {
            PDFPhoto(image: image, shapes: shapes, width: width, height: height, fill: square)
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A block of photo-grid rows kept together on one page. Cells are equal
/// squares with uniform gaps; a partial final row stays left-aligned.
private struct PDFPhotoGrid: View {
    let rows: [[(UUID, UIImage, [AnnotationShape])]]
    let columns: Int
    let side: CGFloat
    let spacing: CGFloat

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: spacing) {
                    ForEach(rows[rowIndex], id: \.0) { entry in
                        PDFPhoto(image: entry.1, shapes: entry.2, width: side, height: side, fill: true)
                    }
                    if rows[rowIndex].count < columns {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PDFPhoto: View {
    let image: UIImage
    let shapes: [AnnotationShape]
    let width: CGFloat
    let height: CGFloat
    /// `true` crops to fill the frame (square cells); `false` fits the whole image.
    var fill: Bool = true

    var body: some View {
        // The frame must come BEFORE clipping so the aspect crop actually
        // constrains the image to width×height (otherwise it keeps its source
        // aspect and overflows the cell).
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: fill ? .fill : .fit)
            .frame(width: width, height: height)
            .clipped()
            .overlay {
                if !shapes.isEmpty {
                    Canvas { context, size in
                        AnnotationRenderer.draw(shapes, in: &context, size: size)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Cover, content, footer

private struct PageCoverPage: View {
    let title: String
    let project: Project
    let companyName: String
    let logo: UIImage?
    let createdAt: Date

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

            Text(title.isEmpty ? "Untitled Page" : title)
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

            Text(createdAt.formatted(date: .long, time: .omitted))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.black)
    }
}

private struct PageContentPage: View {
    let items: [AnyView]

    var body: some View {
        VStack(alignment: .leading, spacing: PagePDFRenderer.itemSpacing) {
            ForEach(items.indices, id: \.self) { index in
                items[index]
            }
            Spacer(minLength: 0)
        }
        .padding(PagePDFRenderer.insets)
        .frame(
            width: PagePDFRenderer.pageSize.width,
            height: PagePDFRenderer.pageSize.height,
            alignment: .topLeading
        )
        .foregroundStyle(.black)
    }
}

private struct PageFooter: View {
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
