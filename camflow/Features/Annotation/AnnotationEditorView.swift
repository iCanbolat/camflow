import SwiftUI
import SwiftData

/// Vector annotation editor: freehand, arrow, rectangle, ellipse, text.
/// Shapes stay editable forever — they're stored as JSON next to the photo
/// and only baked into pixels on export.
struct AnnotationEditorView: View {
    let photo: Photo

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var shapes: [AnnotationShape] = []
    @State private var redoStack: [AnnotationShape] = []
    @State private var tool: AnnotationShape.Kind = .freehand
    @State private var colorHex = TagPalette.colors[0]
    @State private var shapeInProgress: AnnotationShape?
    @State private var image: UIImage?
    @State private var textAnchor: CGPoint?
    @State private var textInput = ""
    @State private var isShowingTextDialog = false

    private let tools: [(AnnotationShape.Kind, String)] = [
        (.freehand, "scribble"),
        (.arrow, "arrow.up.right"),
        (.rectangle, "rectangle"),
        (.ellipse, "circle"),
        (.text, "textformat"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    canvas(for: image)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .navigationTitle("Annotate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(shapes.isEmpty)

                    Button {
                        redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(redoStack.isEmpty)

                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                toolbar
            }
            .task { await loadState() }
            .alert("Add Text", isPresented: $isShowingTextDialog) {
                TextField("Text", text: $textInput)
                Button("Add") { commitText() }
                Button("Cancel", role: .cancel) { textInput = "" }
            }
        }
        .colorScheme(.dark)
    }

    // MARK: - Canvas

    private func canvas(for image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { geometry in
                    let size = geometry.size
                    Canvas { context, canvasSize in
                        AnnotationRenderer.draw(shapes, in: &context, size: canvasSize)
                        if let shapeInProgress {
                            AnnotationRenderer.draw(shapeInProgress, in: &context, size: canvasSize)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(drawGesture(in: size))
                    .onTapGesture { location in
                        guard tool == .text else { return }
                        textAnchor = normalize(location, in: size)
                        isShowingTextDialog = true
                    }
                }
            }
            .padding(.horizontal, 4)
    }

    private func drawGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard tool != .text else { return }
                let point = normalize(value.location, in: size)
                let start = normalize(value.startLocation, in: size)

                switch tool {
                case .freehand:
                    if shapeInProgress == nil {
                        shapeInProgress = AnnotationShape(kind: .freehand, colorHex: colorHex, points: [start])
                    }
                    shapeInProgress?.points.append(point)
                case .arrow, .rectangle, .ellipse:
                    shapeInProgress = AnnotationShape(kind: tool, colorHex: colorHex, points: [start, point])
                case .text:
                    break
                }
            }
            .onEnded { _ in
                if let shape = shapeInProgress {
                    commit(shape)
                }
                shapeInProgress = nil
            }
    }

    private func normalize(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x / size.width, 0), 1),
            y: min(max(point.y / size.height, 0), 1)
        )
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ForEach(TagPalette.colors, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 26, height: 26)
                        .overlay {
                            if hex == colorHex {
                                Circle().strokeBorder(.white, lineWidth: 2)
                            }
                        }
                        .onTapGesture { colorHex = hex }
                }
            }

            HStack(spacing: 8) {
                ForEach(tools, id: \.0) { kind, icon in
                    Button {
                        tool = kind
                    } label: {
                        Image(systemName: icon)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(tool == kind ? .black : .white)
                            .frame(width: 52, height: 40)
                            .background(
                                tool == kind ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.15)),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.85))
    }

    // MARK: - Actions

    private func loadState() async {
        shapes = AnnotationDocument.decode(photo.annotationData).shapes
        let fileName = photo.fileName
        image = await Task.detached {
            FileStorage.load(fileName, in: .photos).flatMap(UIImage.init(data:))
        }.value
    }

    private func commit(_ shape: AnnotationShape) {
        shapes.append(shape)
        redoStack.removeAll()
    }

    private func commitText() {
        let text = textInput.trimmingCharacters(in: .whitespaces)
        textInput = ""
        guard !text.isEmpty, let anchor = textAnchor else { return }
        commit(AnnotationShape(kind: .text, colorHex: colorHex, points: [anchor], text: text))
        textAnchor = nil
    }

    private func undo() {
        guard let last = shapes.popLast() else { return }
        redoStack.append(last)
    }

    private func redo() {
        guard let last = redoStack.popLast() else { return }
        shapes.append(last)
    }

    private func save() {
        photo.annotationData = AnnotationDocument(shapes: shapes).encoded()
        PhotoStore(context: modelContext).touch(photo)
        dismiss()
    }
}
