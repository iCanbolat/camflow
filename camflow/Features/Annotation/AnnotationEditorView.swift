import SwiftUI
import SwiftData

/// Vector annotation editor. Freehand is drawn by dragging; arrow / rectangle /
/// ellipse / text are inserted as objects you then drag to **move** and resize
/// via handles. Shapes stay editable forever — stored as JSON next to the photo
/// and only baked into pixels on export.
struct AnnotationEditorView: View {
    private let loadImage: () async -> UIImage?
    private let initialAnnotationData: Data?
    private let onSave: (Data?) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        loadImage: @escaping () async -> UIImage?,
        annotationData: Data?,
        onSave: @escaping (Data?) -> Void
    ) {
        self.loadImage = loadImage
        self.initialAnnotationData = annotationData
        self.onSave = onSave
    }

    /// `select` manipulates existing shapes; `freehand` draws a new stroke.
    private enum Tool { case select, freehand }

    /// What the in-flight drag is doing. Captured at drag start so each frame
    /// applies a delta against the shape's *original* geometry (not the running
    /// one), which keeps moves/resizes stable.
    private enum DragOp {
        case idle
        case draw
        case move(id: UUID, original: AnnotationShape, start: CGPoint)
        case resize(id: UUID, handle: Int, original: AnnotationShape)
    }

    @State private var shapes: [AnnotationShape] = []
    /// Snapshot-based history so move/resize/edit/delete all undo uniformly.
    @State private var undoStack: [[AnnotationShape]] = []
    @State private var redoStack: [[AnnotationShape]] = []
    @State private var tool: Tool = .select
    @State private var colorHex = TagPalette.colors[0]
    @State private var selectedID: UUID?
    @State private var shapeInProgress: AnnotationShape?
    @State private var dragOp: DragOp = .idle
    @State private var dragBegan = false
    @State private var image: UIImage?
    @State private var textInput = ""
    @State private var editingTextID: UUID?
    @State private var isShowingTextDialog = false

    private let handleTouchRadius: CGFloat = 24
    private let hitTolerance: CGFloat = 16

    private var selectedShape: AnnotationShape? {
        guard let selectedID else { return nil }
        return shapes.first { $0.id == selectedID }
    }

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
                    Button { undo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(undoStack.isEmpty)

                    Button { redo() } label: {
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
            .alert(editingTextID == nil ? "Add Text" : "Edit Text", isPresented: $isShowingTextDialog) {
                TextField("Text", text: $textInput)
                Button(editingTextID == nil ? "Add" : "Save") { commitText() }
                Button("Cancel", role: .cancel) { textInput = ""; editingTextID = nil }
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
                        if let selectedShape {
                            drawSelection(selectedShape, in: &context, size: canvasSize)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(canvasDrag(in: size))
                    .onTapGesture { location in handleTap(at: location, in: size) }
                }
            }
            .padding(.horizontal, 4)
    }

    private func canvasDrag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !dragBegan {
                    dragBegan = true
                    beginDrag(at: value.startLocation, in: size)
                }
                updateDrag(to: value.location, in: size)
            }
            .onEnded { _ in
                endDrag()
                dragBegan = false
            }
    }

    // MARK: - Drag state machine

    private func beginDrag(at location: CGPoint, in size: CGSize) {
        let startN = normalize(location, in: size)

        if tool == .freehand {
            selectedID = nil
            shapeInProgress = AnnotationShape(kind: .freehand, colorHex: colorHex, points: [startN])
            dragOp = .draw
            return
        }

        // Select mode: resize handle of the selection → move a hit shape → deselect.
        if let selected = selectedShape, let handle = handleIndex(for: selected, at: location, in: size) {
            pushUndo()
            dragOp = .resize(id: selected.id, handle: handle, original: selected)
            return
        }
        if let hitID = topmostShapeID(at: location, in: size),
           let original = shapes.first(where: { $0.id == hitID }) {
            selectedID = hitID
            pushUndo()
            dragOp = .move(id: hitID, original: original, start: startN)
            return
        }
        selectedID = nil
        dragOp = .idle
    }

    private func updateDrag(to location: CGPoint, in size: CGSize) {
        let currentN = normalize(location, in: size)
        switch dragOp {
        case .draw:
            shapeInProgress?.points.append(currentN)
        case .move(let id, let original, let start):
            guard let i = shapes.firstIndex(where: { $0.id == id }) else { return }
            let dx = currentN.x - start.x
            let dy = currentN.y - start.y
            shapes[i].points = original.points.map {
                CGPoint(x: clamp01($0.x + dx), y: clamp01($0.y + dy))
            }
        case .resize(let id, let handle, let original):
            guard let i = shapes.firstIndex(where: { $0.id == id }) else { return }
            shapes[i] = resized(original, handle: handle, to: currentN)
        case .idle:
            break
        }
    }

    private func endDrag() {
        if case .draw = dragOp {
            if let stroke = shapeInProgress, stroke.points.count > 1 {
                pushUndo()
                shapes.append(stroke)
            }
            shapeInProgress = nil
        }
        dragOp = .idle
    }

    private func handleTap(at location: CGPoint, in size: CGSize) {
        guard tool == .select else { return }
        if let hitID = topmostShapeID(at: location, in: size) {
            // Tapping an already-selected text shape opens its editor.
            if let shape = shapes.first(where: { $0.id == hitID }),
               shape.kind == .text, selectedID == hitID {
                editingTextID = hitID
                textInput = shape.text ?? ""
                isShowingTextDialog = true
            } else {
                selectedID = hitID
            }
        } else {
            selectedID = nil
        }
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
                        .onTapGesture {
                            colorHex = hex
                            applyColorToSelection()
                        }
                }
            }

            HStack(spacing: 6) {
                modeButton(.select, icon: "cursorarrow")
                modeButton(.freehand, icon: "scribble.variable")
                insertButton(icon: "arrow.up.right") { insertShape(.arrow) }
                insertButton(icon: "rectangle") { insertShape(.rectangle) }
                insertButton(icon: "circle") { insertShape(.ellipse) }
                insertButton(icon: "textformat") { startAddText() }

                Button(role: .destructive) { deleteSelection() } label: {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(selectedID == nil ? .white.opacity(0.3) : .red)
                        .frame(width: 44, height: 40)
                        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }
                .disabled(selectedID == nil)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.85))
    }

    private func modeButton(_ mode: Tool, icon: String) -> some View {
        Button {
            tool = mode
            if mode == .freehand { selectedID = nil }
        } label: {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tool == mode ? .black : .white)
                .frame(width: 44, height: 40)
                .background(
                    tool == mode ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.15)),
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
    }

    private func insertButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 40)
                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Mutations

    /// Drops a default-sized shape in the middle of the image and selects it so
    /// it can be dragged/resized immediately.
    private func insertShape(_ kind: AnnotationShape.Kind) {
        let shape: AnnotationShape
        switch kind {
        case .rectangle:
            shape = AnnotationShape(kind: .rectangle, colorHex: colorHex,
                                    points: [CGPoint(x: 0.32, y: 0.42), CGPoint(x: 0.68, y: 0.58)])
        case .ellipse:
            shape = AnnotationShape(kind: .ellipse, colorHex: colorHex,
                                    points: [CGPoint(x: 0.32, y: 0.4), CGPoint(x: 0.68, y: 0.6)])
        case .arrow:
            shape = AnnotationShape(kind: .arrow, colorHex: colorHex,
                                    points: [CGPoint(x: 0.34, y: 0.5), CGPoint(x: 0.66, y: 0.5)])
        case .freehand, .text:
            return
        }
        pushUndo()
        shapes.append(shape)
        selectedID = shape.id
        tool = .select
    }

    private func startAddText() {
        editingTextID = nil
        textInput = ""
        isShowingTextDialog = true
    }

    private func commitText() {
        let text = textInput.trimmingCharacters(in: .whitespaces)
        textInput = ""
        defer { editingTextID = nil }
        guard !text.isEmpty else { return }

        if let id = editingTextID, let i = shapes.firstIndex(where: { $0.id == id }) {
            pushUndo()
            shapes[i].text = text
        } else {
            pushUndo()
            let shape = AnnotationShape(kind: .text, colorHex: colorHex,
                                       points: [CGPoint(x: 0.5, y: 0.46)], text: text)
            shapes.append(shape)
            selectedID = shape.id
            tool = .select
        }
    }

    private func applyColorToSelection() {
        guard let id = selectedID, let i = shapes.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        shapes[i].colorHex = colorHex
    }

    private func deleteSelection() {
        guard let id = selectedID, let i = shapes.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        shapes.remove(at: i)
        selectedID = nil
    }

    // MARK: - Undo / redo (snapshot based)

    private func pushUndo() {
        undoStack.append(shapes)
        redoStack.removeAll()
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(shapes)
        shapes = previous
        dropSelectionIfMissing()
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(shapes)
        shapes = next
        dropSelectionIfMissing()
    }

    private func dropSelectionIfMissing() {
        if let id = selectedID, !shapes.contains(where: { $0.id == id }) {
            selectedID = nil
        }
    }

    // MARK: - Hit testing & geometry (screen space)

    private func denorm(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
    }

    private func handleIndex(for shape: AnnotationShape, at loc: CGPoint, in size: CGSize) -> Int? {
        switch shape.kind {
        case .rectangle, .ellipse, .arrow:
            for (i, p) in shape.points.enumerated() where dist(denorm(p, size), loc) <= handleTouchRadius {
                return i
            }
            return nil
        case .text:
            return dist(textScaleHandle(shape, size), loc) <= handleTouchRadius ? 1 : nil
        case .freehand:
            return nil
        }
    }

    private func topmostShapeID(at loc: CGPoint, in size: CGSize) -> UUID? {
        for shape in shapes.reversed() where hitTest(shape, loc, size) {
            return shape.id
        }
        return nil
    }

    private func hitTest(_ shape: AnnotationShape, _ loc: CGPoint, _ size: CGSize) -> Bool {
        let pts = shape.points.map { denorm($0, size) }
        switch shape.kind {
        case .rectangle, .ellipse:
            guard pts.count == 2 else { return false }
            return rect(pts[0], pts[1]).insetBy(dx: -hitTolerance, dy: -hitTolerance).contains(loc)
        case .arrow:
            guard pts.count == 2 else { return false }
            return distToSegment(loc, pts[0], pts[1]) <= hitTolerance
        case .text:
            return textBox(shape, size).insetBy(dx: -hitTolerance, dy: -hitTolerance).contains(loc)
        case .freehand:
            guard pts.count > 1 else { return false }
            for i in 1..<pts.count where distToSegment(loc, pts[i - 1], pts[i]) <= hitTolerance {
                return true
            }
            return false
        }
    }

    private func resized(_ original: AnnotationShape, handle: Int, to currentN: CGPoint) -> AnnotationShape {
        var s = original
        switch s.kind {
        case .rectangle, .ellipse, .arrow:
            if handle < s.points.count {
                s.points[handle] = CGPoint(x: clamp01(currentN.x), y: clamp01(currentN.y))
            }
        case .text:
            let anchor = original.points.first ?? CGPoint(x: 0.5, y: 0.5)
            let count = max(CGFloat((original.text ?? "").count), 1)
            // Handle sits at the box's right edge; keep it tracking the finger.
            let raw = (currentN.x - anchor.x) / (count * 0.6)
            s.fontScale = min(max(raw, 0.02), 0.4)
        case .freehand:
            break
        }
        return s
    }

    // Renderer measures text precisely inside the Canvas; this approximation is
    // only for the selection box and resize handle, which don't need to be exact.
    private func textBox(_ shape: AnnotationShape, _ size: CGSize) -> CGRect {
        let anchor = denorm(shape.points.first ?? CGPoint(x: 0.5, y: 0.5), size)
        let fontSize = max(12, shape.fontScale * size.width)
        let count = max((shape.text ?? "").count, 1)
        let width = CGFloat(count) * fontSize * 0.6
        let height = fontSize * 1.3
        return CGRect(x: anchor.x, y: anchor.y, width: width, height: height)
    }

    private func textScaleHandle(_ shape: AnnotationShape, _ size: CGSize) -> CGPoint {
        let box = textBox(shape, size)
        return CGPoint(x: box.maxX, y: box.maxY)
    }

    // MARK: - Selection overlay

    private func drawSelection(_ shape: AnnotationShape, in context: inout GraphicsContext, size: CGSize) {
        let dash = StrokeStyle(lineWidth: 1, dash: [5, 4])
        let outline = GraphicsContext.Shading.color(.white.opacity(0.9))

        switch shape.kind {
        case .rectangle, .ellipse, .arrow:
            let pts = shape.points.map { denorm($0, size) }
            guard pts.count == 2 else { return }
            if shape.kind != .arrow {
                context.stroke(Path(rect(pts[0], pts[1])), with: outline, style: dash)
            }
            for p in pts { drawHandle(at: p, in: &context) }
        case .text:
            context.stroke(Path(roundedRect: textBox(shape, size), cornerRadius: 3), with: outline, style: dash)
            drawHandle(at: textScaleHandle(shape, size), in: &context)
        case .freehand:
            let pts = shape.points.map { denorm($0, size) }
            context.stroke(Path(boundingBox(pts)), with: outline, style: dash)
        }
    }

    private func drawHandle(at p: CGPoint, in context: inout GraphicsContext) {
        let r: CGFloat = 7
        let box = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: box), with: .color(.white))
        context.stroke(Path(ellipseIn: box), with: .color(.black), style: StrokeStyle(lineWidth: 1.5))
    }

    // MARK: - Math

    private func normalize(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: clamp01(p.x / size.width), y: clamp01(p.y / size.height))
    }

    private func clamp01(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func boundingBox(_ pts: [CGPoint]) -> CGRect {
        guard let first = pts.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in pts {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func distToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        if dx == 0 && dy == 0 { return dist(p, a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)))
        return dist(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    // MARK: - Load / save

    private func loadState() async {
        shapes = AnnotationDocument.decode(initialAnnotationData).shapes
        image = await loadImage()
    }

    private func save() {
        onSave(AnnotationDocument(shapes: shapes).encoded())
        dismiss()
    }
}

extension AnnotationEditorView {
    /// Annotate a persisted photo: loads its image off-main and writes the
    /// edited annotation back through `PhotoStore`.
    init(photo: Photo, context: ModelContext) {
        self.init(
            loadImage: {
                let fileName = photo.fileName
                return await Task.detached {
                    FileStorage.load(fileName, in: .photos).flatMap(UIImage.init(data:))
                }.value
            },
            annotationData: photo.annotationData,
            onSave: { data in
                photo.annotationData = data
                PhotoStore(context: context).touch(photo)
            }
        )
    }
}
