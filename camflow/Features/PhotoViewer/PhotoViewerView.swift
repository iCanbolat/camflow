import SwiftUI
import SwiftData
import AVKit

/// Full-screen photo viewer: horizontal swipe between photos, pinch zoom,
/// live annotation overlay, tag/caption editing, share, delete.
struct PhotoViewerView: View {
    let photos: [Photo]

    @State private var index: Int
    @State private var isShowingAnnotationEditor = false
    @State private var isShowingTagPicker = false
    @State private var isShowingShareSheet = false
    @State private var isShowingProjectPicker = false
    @State private var isEditingCaption = false
    @State private var captionInput = ""
    @State private var isConfirmingDelete = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    init(photos: [Photo], initialIndex: Int = 0) {
        self.photos = photos
        _index = State(initialValue: min(max(initialIndex, 0), max(photos.count - 1, 0)))
    }

    private var currentPhoto: Photo? {
        photos.indices.contains(index) ? photos[index] : nil
    }

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                Group {
                    if photo.isVideo {
                        VideoPlayerPageView(photo: photo)
                    } else {
                        PhotoPageView(photo: photo)
                    }
                }
                .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(.black)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black.opacity(0.6), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let photo = currentPhoto {
                    VStack(spacing: 0) {
                        Text(photo.project?.name ?? String(localized: "Unassigned"))
                            .font(.subheadline.weight(.semibold))
                        Text(photo.capturedAt, format: .dateTime.day().month().hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if currentPhoto?.isVideo != true {
                    Button {
                        isShowingAnnotationEditor = true
                    } label: {
                        Image(systemName: "pencil.tip.crop.circle")
                    }
                }
                Menu {
                    Button {
                        isShowingTagPicker = true
                    } label: {
                        Label("Tags", systemImage: "tag")
                    }
                    Button {
                        captionInput = currentPhoto?.caption ?? ""
                        isEditingCaption = true
                    } label: {
                        Label("Edit Caption", systemImage: "text.below.photo")
                    }
                    Button {
                        isShowingProjectPicker = true
                    } label: {
                        Label("Assign to Project", systemImage: "folder")
                    }
                    Button {
                        isShowingShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label(currentPhoto?.isVideo == true ? "Delete Video" : "Delete Photo", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let photo = currentPhoto {
                infoBar(for: photo)
            }
        }
        .fullScreenCover(isPresented: $isShowingAnnotationEditor) {
            if let photo = currentPhoto {
                AnnotationEditorView(photo: photo)
            }
        }
        .sheet(isPresented: $isShowingTagPicker) {
            if let photo = currentPhoto {
                TagPickerSheet(photos: [photo])
            }
        }
        .sheet(isPresented: $isShowingShareSheet) {
            if let photo = currentPhoto {
                ShareOptionsSheet(photos: [photo])
            }
        }
        .sheet(isPresented: $isShowingProjectPicker) {
            ProjectPickerSheet(selectedProject: Binding(
                get: { currentPhoto?.project },
                set: { newProject in
                    guard let photo = currentPhoto else { return }
                    photo.project = newProject
                    newProject?.updatedAt = .now
                    PhotoStore(context: modelContext).touch(photo)
                }
            ))
        }
        .alert("Edit Caption", isPresented: $isEditingCaption) {
            TextField("Caption", text: $captionInput)
            Button("Save") {
                guard let photo = currentPhoto else { return }
                photo.caption = captionInput.trimmingCharacters(in: .whitespaces)
                PhotoStore(context: modelContext).touch(photo)
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this photo?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let photo = currentPhoto {
                    PhotoStore(context: modelContext).softDelete(photo)
                }
                dismiss()
            }
        }
    }

    private func infoBar(for photo: Photo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !photo.caption.isEmpty {
                Text(photo.caption)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }

            if !photo.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(photo.tags.filter { $0.deletedAt == nil }) { tag in
                            LabelChip(name: tag.name, colorHex: tag.colorHex)
                        }
                    }
                }
            }

            HStack(spacing: 16) {
                if let duration = photo.formattedDuration {
                    Label(duration, systemImage: "video.fill")
                }
                if photo.latitude != nil {
                    Label("GPS", systemImage: "location.fill")
                }
                if photo.annotationData != nil {
                    Label("Annotated", systemImage: "pencil.tip")
                }
                if photo.source == .imported {
                    Label("Imported", systemImage: "square.and.arrow.down")
                }
                Spacer()
                Text("\(index + 1) / \(photos.count)")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.black.opacity(0.6))
    }
}

/// One zoomable page with the photo and its annotation overlay.
struct PhotoPageView: View {
    let photo: Photo

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ZoomableContainer {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .overlay {
                            let document = AnnotationDocument.decode(photo.annotationData)
                            if !document.shapes.isEmpty {
                                Canvas { context, size in
                                    AnnotationRenderer.draw(document.shapes, in: &context, size: size)
                                }
                                .allowsHitTesting(false)
                            }
                        }
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .task(id: photo.fileName) {
            let fileName = photo.fileName
            image = await Task.detached {
                FileStorage.load(fileName, in: .photos).flatMap(UIImage.init(data:))
            }.value
        }
    }
}

/// Video page: system playback controls via AVKit. The player is released as
/// soon as the page scrolls offscreen — TabView keeps neighbor pages alive,
/// and two live players would both play audio and hold decoder memory.
struct VideoPlayerPageView: View {
    let photo: Photo

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .task(id: photo.fileName) {
            player = AVPlayer(url: FileStorage.url(for: photo.fileName, in: .photos))
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

/// Pinch-to-zoom + pan container. Pan only engages while zoomed so it
/// doesn't fight the pager; double-tap toggles zoom.
struct ZoomableContainer<Content: View>: View {
    @ViewBuilder let content: Content

    @State private var scale: CGFloat = 1
    @State private var steadyScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero

    var body: some View {
        content
            .scaleEffect(scale)
            .offset(offset)
            .gesture(magnification)
            .simultaneousGesture(scale > 1 ? pan : nil)
            .onTapGesture(count: 2) {
                withAnimation(.spring(duration: 0.3)) {
                    if scale > 1 {
                        (scale, steadyScale, offset, steadyOffset) = (1, 1, .zero, .zero)
                    } else {
                        scale = 2.5
                        steadyScale = 2.5
                    }
                }
            }
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = max(1, steadyScale * value.magnification)
            }
            .onEnded { _ in
                steadyScale = scale
                if scale <= 1.05 {
                    withAnimation(.spring(duration: 0.25)) {
                        (scale, steadyScale, offset, steadyOffset) = (1, 1, .zero, .zero)
                    }
                }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: steadyOffset.width + value.translation.width,
                    height: steadyOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                steadyOffset = offset
            }
    }
}
