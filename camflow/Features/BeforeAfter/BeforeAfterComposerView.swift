import SwiftUI
import SwiftData

/// Composes a before/after pair: pick two photos, choose a layout, preview
/// (including an interactive slider compare), save and export with badges.
struct BeforeAfterComposerView: View {
    let project: Project
    var existingPair: BeforeAfterPair?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private enum Slot {
        case before
        case after
    }

    private enum PreviewMode: Hashable {
        case layout
        case slider
    }

    @State private var beforePhoto: Photo?
    @State private var afterPhoto: Photo?
    @State private var layout: BeforeAfterPair.Layout = .sideBySide
    @State private var previewMode: PreviewMode = .layout
    @State private var sliderPosition: CGFloat = 0.5
    @State private var pickingSlot: Slot?
    @State private var beforeImage: UIImage?
    @State private var afterImage: UIImage?
    @State private var exportURL: URL?
    @State private var isExporting = false

    private var bothSelected: Bool {
        beforePhoto != nil && afterPhoto != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                slotButtons

                if bothSelected {
                    Picker("Preview", selection: $previewMode) {
                        Text("Layout").tag(PreviewMode.layout)
                        Text("Slider").tag(PreviewMode.slider)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if previewMode == .layout {
                        Picker("Arrangement", selection: $layout) {
                            Label("Side by Side", systemImage: "rectangle.split.2x1").tag(BeforeAfterPair.Layout.sideBySide)
                            Label("Stacked", systemImage: "rectangle.split.1x2").tag(BeforeAfterPair.Layout.stacked)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }

                    preview
                        .padding(.horizontal)
                } else {
                    ContentUnavailableView {
                        Label("Pick Both Photos", systemImage: "photo.on.rectangle.angled")
                    } description: {
                        Text("Choose a before and an after photo from this project.")
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .navigationTitle("Before / After")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!bothSelected)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if bothSelected {
                    exportBar
                }
            }
            .sheet(isPresented: Binding(
                get: { pickingSlot != nil },
                set: { if !$0 { pickingSlot = nil } }
            )) {
                ProjectPhotoPickerSheet(project: project, singleSelection: true, excludesVideos: true) { photos in
                    guard let photo = photos.first else { return }
                    switch pickingSlot {
                    case .before: beforePhoto = photo
                    case .after: afterPhoto = photo
                    case nil: break
                    }
                }
            }
            .task(id: beforePhoto?.id) { beforeImage = await loadImage(beforePhoto) }
            .task(id: afterPhoto?.id) { afterImage = await loadImage(afterPhoto) }
            .onChange(of: beforePhoto?.id) { exportURL = nil }
            .onChange(of: afterPhoto?.id) { exportURL = nil }
            .onChange(of: layout) { exportURL = nil }
            .onAppear(perform: loadExisting)
        }
    }

    // MARK: - Slots

    private var slotButtons: some View {
        HStack(spacing: 12) {
            slotButton(.before, photo: beforePhoto, label: "BEFORE")
            slotButton(.after, photo: afterPhoto, label: "AFTER")
        }
        .padding(.horizontal)
    }

    private func slotButton(_ slot: Slot, photo: Photo?, label: String) -> some View {
        Button {
            pickingSlot = slot
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.fill.tertiary)
                if let photo {
                    PhotoCell(photo: photo)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                        Text(verbatim: label)
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(height: 110)
            .overlay(alignment: .topLeading) {
                if photo != nil {
                    BadgeLabel(text: label)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        if let beforeImage, let afterImage {
            if previewMode == .slider {
                SliderCompareView(before: beforeImage, after: afterImage, position: $sliderPosition)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                BeforeAfterCompositeView(
                    before: beforeImage,
                    beforeShapes: shapes(of: beforePhoto),
                    after: afterImage,
                    afterShapes: shapes(of: afterPhoto),
                    layout: layout
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private var exportBar: some View {
        HStack {
            if isExporting {
                ProgressView()
                Text("Preparing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share Composite", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    Task { await export() }
                } label: {
                    Label("Export Composite", systemImage: "photo.badge.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Actions

    private func loadExisting() {
        guard let existingPair else { return }
        beforePhoto = project.activePhotos.first { $0.id == existingPair.beforePhotoID }
        afterPhoto = project.activePhotos.first { $0.id == existingPair.afterPhotoID }
        layout = existingPair.layout
    }

    private func shapes(of photo: Photo?) -> [AnnotationShape] {
        AnnotationDocument.decode(photo?.annotationData).shapes
    }

    private func loadImage(_ photo: Photo?) async -> UIImage? {
        guard let fileName = photo?.fileName else { return nil }
        return await Task.detached {
            FileStorage.load(fileName, in: .photos).flatMap(UIImage.init(data:))
        }.value
    }

    private func save() {
        guard let beforePhoto, let afterPhoto else { return }
        let store = BeforeAfterStore(context: modelContext)
        if let existingPair {
            existingPair.beforePhotoID = beforePhoto.id
            existingPair.afterPhotoID = afterPhoto.id
            existingPair.layout = layout
            store.touch(existingPair)
        } else {
            store.create(
                beforePhotoID: beforePhoto.id,
                afterPhotoID: afterPhoto.id,
                layout: layout,
                project: project
            )
        }
        dismiss()
    }

    private func export() async {
        guard let beforeImage, let afterImage else { return }
        isExporting = true
        defer { isExporting = false }

        let composite = BeforeAfterCompositeView(
            before: beforeImage,
            beforeShapes: shapes(of: beforePhoto),
            after: afterImage,
            afterShapes: shapes(of: afterPhoto),
            layout: layout
        )
        .frame(width: 2048)

        let renderer = ImageRenderer(content: composite)
        renderer.proposedSize = ProposedViewSize(width: 2048, height: nil)
        renderer.scale = 1

        guard let image = renderer.uiImage,
              let data = image.jpegData(compressionQuality: 0.9) else { return }

        let url = FileManager.default.temporaryDirectory
            .appending(path: "BeforeAfter_\(project.name.components(separatedBy: CharacterSet.alphanumerics.inverted).joined())_\(UUID().uuidString.prefix(6)).jpg")
        if (try? data.write(to: url, options: .atomic)) != nil {
            exportURL = url
        }
    }
}

// MARK: - Shared composite pieces

struct BadgeLabel: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.65), in: Capsule())
    }
}

/// The composition rendered both on screen and to pixels on export.
struct BeforeAfterCompositeView: View {
    let before: UIImage
    let beforeShapes: [AnnotationShape]
    let after: UIImage
    let afterShapes: [AnnotationShape]
    let layout: BeforeAfterPair.Layout

    var body: some View {
        Group {
            switch layout {
            case .sideBySide:
                HStack(spacing: 3) {
                    block(before, shapes: beforeShapes, badge: "BEFORE")
                    block(after, shapes: afterShapes, badge: "AFTER")
                }
            case .stacked:
                VStack(spacing: 3) {
                    block(before, shapes: beforeShapes, badge: "BEFORE")
                    block(after, shapes: afterShapes, badge: "AFTER")
                }
            }
        }
        .background(.black)
    }

    private func block(_ image: UIImage, shapes: [AnnotationShape], badge: String) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                if !shapes.isEmpty {
                    Canvas { context, size in
                        AnnotationRenderer.draw(shapes, in: &context, size: size)
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                GeometryReader { geometry in
                    Text(verbatim: badge)
                        .font(.system(size: max(11, geometry.size.width * 0.045), weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, geometry.size.width * 0.02)
                        .padding(.vertical, geometry.size.width * 0.012)
                        .background(.black.opacity(0.65), in: Capsule())
                        .padding(geometry.size.width * 0.025)
                }
            }
    }
}

/// Interactive compare: drag the divider to wipe between before and after.
struct SliderCompareView: View {
    let before: UIImage
    let after: UIImage
    @Binding var position: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Image(uiImage: before)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: geometry.size.height)
                    .clipped()

                Image(uiImage: after)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: geometry.size.height)
                    .clipped()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: width * position)
                    }

                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .shadow(radius: 2)
                    .overlay {
                        Circle()
                            .fill(.white)
                            .frame(width: 28, height: 28)
                            .overlay {
                                Image(systemName: "arrow.left.and.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.black)
                            }
                    }
                    .offset(x: width * position - 1)
            }
            .overlay(alignment: .topLeading) {
                BadgeLabel(text: "AFTER").padding(8)
            }
            .overlay(alignment: .topTrailing) {
                BadgeLabel(text: "BEFORE").padding(8)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        position = min(max(value.location.x / width, 0.02), 0.98)
                    }
            )
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
    }
}
