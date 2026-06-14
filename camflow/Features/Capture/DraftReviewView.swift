import SwiftUI
import AVKit

/// Reviews the captured-but-not-yet-saved batch side by side. Each draft can be
/// described and (photos) annotated; drafts can be deleted; "Done" submits the
/// whole batch via the capture screen's `onSubmit`.
struct DraftReviewView: View {
    @Binding var drafts: [CapturedDraft]
    let projectName: String?
    let onSubmit: () async -> Void

    @State private var index = 0
    @State private var isShowingAnnotation = false
    @State private var isSubmitting = false
    @FocusState private var isDescriptionFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var currentDraft: CapturedDraft? {
        drafts.indices.contains(index) ? drafts[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                pager
                filmstrip
                editorBar
            }

            if isSubmitting {
                Color.black.opacity(0.45).ignoresSafeArea()
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.4)
            }
        }
        .statusBarHidden()
        .fullScreenCover(isPresented: $isShowingAnnotation) {
            if let draft = currentDraft, !draft.isVideo {
                AnnotationEditorView(
                    loadImage: { draftImage(draft) },
                    annotationData: draft.annotationData,
                    onSave: { draft.annotationData = $0 }
                )
            }
        }
        .onChange(of: drafts.count) { _, newCount in
            if newCount == 0 {
                dismiss()
            } else if index >= newCount {
                index = newCount - 1
            }
        }
        .onChange(of: index) { _, _ in
            // Swiping/selecting another draft dismisses the keyboard.
            isDescriptionFocused = false
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.15), in: Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text(projectName ?? String(localized: "Unassigned"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if !drafts.isEmpty {
                    Text("\(index + 1) of \(drafts.count)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()

            // Balances the close button so the title stays centered.
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var pager: some View {
        TabView(selection: $index) {
            ForEach(Array(drafts.enumerated()), id: \.element.id) { offset, draft in
                DraftPageView(draft: draft)
                    .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .overlay {
            // Tapping the photo area while editing dismisses the keyboard.
            if isDescriptionFocused {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { isDescriptionFocused = false }
            }
        }
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(drafts.enumerated()), id: \.element.id) { offset, draft in
                        Button {
                            withAnimation { index = offset }
                        } label: {
                            Image(uiImage: draft.thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(
                                            offset == index ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.3)),
                                            lineWidth: offset == index ? 3 : 1
                                        )
                                }
                                .overlay(alignment: .bottomLeading) {
                                    if draft.isVideo {
                                        Image(systemName: "video.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.white)
                                            .padding(4)
                                    }
                                }
                                .overlay(alignment: .topTrailing) {
                                    if draft.annotationData != nil {
                                        Image(systemName: "pencil.tip")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.white)
                                            .padding(3)
                                            .background(.black.opacity(0.5), in: Circle())
                                            .padding(2)
                                    }
                                }
                        }
                        .id(offset)
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 72)
            .onChange(of: index) { _, newIndex in
                withAnimation { proxy.scrollTo(newIndex, anchor: .center) }
            }
        }
    }

    private var editorBar: some View {
        VStack(spacing: 12) {
            if let draft = currentDraft {
                TextField("Description", text: Bindable(draft).caption, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($isDescriptionFocused)
                    .padding(12)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 12) {
                    if !draft.isVideo {
                        Button {
                            isShowingAnnotation = true
                        } label: {
                            Label("Annotate", systemImage: "scribble.variable")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.white.opacity(0.15), in: Capsule())
                        }
                    }

                    Button {
                        deleteCurrent()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.15), in: Capsule())
                    }

                    Spacer()

                    Button {
                        Task {
                            isSubmitting = true
                            await onSubmit()
                        }
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(.white, in: Capsule())
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    // MARK: - Actions

    private func deleteCurrent() {
        guard drafts.indices.contains(index) else { return }
        if let url = drafts[index].videoURL {
            try? FileManager.default.removeItem(at: url)
        }
        drafts.remove(at: index)
    }

    private func draftImage(_ draft: CapturedDraft) -> UIImage? {
        if case .photo(let data) = draft.media {
            return UIImage(data: data)
        }
        return nil
    }
}

/// One full-bleed page: a zoomable photo with its live annotation overlay, or a
/// video player. Mirrors `PhotoPageView` but reads from an in-memory draft.
private struct DraftPageView: View {
    let draft: CapturedDraft

    @State private var image: UIImage?

    var body: some View {
        Group {
            if draft.isVideo {
                if let url = draft.videoURL {
                    VideoPlayer(player: AVPlayer(url: url))
                } else {
                    ProgressView().tint(.white)
                }
            } else if let image {
                ZoomableContainer {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .overlay {
                            let document = AnnotationDocument.decode(draft.annotationData)
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
        .task(id: draft.id) {
            guard case .photo(let data) = draft.media else { return }
            image = await Task.detached { UIImage(data: data) }.value
        }
    }
}
