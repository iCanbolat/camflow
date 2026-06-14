import SwiftUI

/// Editor for a single `PageBlock`. Renders kind-specific content plus a shared
/// options menu (move/delete + per-kind settings).
struct PageBlockEditor: View {
    @Binding var block: PageBlock
    let project: Project
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            optionsMenu
        }
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .heading:
            RichTextBox(text: textBinding, placeholder: "Heading", font: headingFont, minHeight: 40)
        case .paragraph:
            RichTextBox(text: textBinding, placeholder: "Write something…", font: .body, minHeight: 80)
        case .bulletList:
            listEditor(numbered: false)
        case .numberedList:
            listEditor(numbered: true)
        case .checklist:
            checklistEditor
        case .divider:
            Rectangle()
                .fill(.quaternary)
                .frame(height: 2)
                .padding(.vertical, 6)
        case .photo, .photoGrid:
            PagePhotoBlockEditor(block: $block, project: project)
        }
    }

    private var optionsMenu: some View {
        Menu {
            if block.kind == .heading {
                Picker("Heading Level", selection: headingLevelBinding) {
                    Text("Title").tag(1)
                    Text("Heading").tag(2)
                    Text("Subheading").tag(3)
                }
                Divider()
            }
            Button(action: onMoveUp) { Label("Move Up", systemImage: "arrow.up") }
            Button(action: onMoveDown) { Label("Move Down", systemImage: "arrow.down") }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete Block", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 32)
                .contentShape(Rectangle())
        }
    }

    private var headingFont: Font {
        switch block.headingLevel ?? 2 {
        case 1: return .title.weight(.bold)
        case 3: return .headline
        default: return .title2.weight(.bold)
        }
    }

    // MARK: - Bindings

    private var textBinding: Binding<AttributedString> {
        Binding(
            get: { block.text ?? AttributedString("") },
            set: { block.text = $0 }
        )
    }

    private var headingLevelBinding: Binding<Int> {
        Binding(get: { block.headingLevel ?? 2 }, set: { block.headingLevel = $0 })
    }

    // MARK: - Lists

    private func listEditor(numbered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let items = block.listItems ?? []
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    Text(numbered ? "\(index + 1)." : "•")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20, alignment: .trailing)
                        .padding(.top, 8)
                    RichTextBox(text: listItemBinding(index), placeholder: "List item", font: .body, minHeight: 34)
                    Button { removeListItem(index) } label: {
                        Image(systemName: "minus.circle").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
            Button { addListItem() } label: {
                Label("Add item", systemImage: "plus").font(.caption)
            }
        }
    }

    private func listItemBinding(_ index: Int) -> Binding<AttributedString> {
        Binding(
            get: { (block.listItems?.indices.contains(index) ?? false) ? block.listItems![index] : AttributedString("") },
            set: { newValue in
                guard block.listItems?.indices.contains(index) == true else { return }
                block.listItems![index] = newValue
            }
        )
    }

    private func addListItem() {
        if block.listItems == nil { block.listItems = [] }
        block.listItems!.append(AttributedString(""))
    }

    private func removeListItem(_ index: Int) {
        guard block.listItems?.indices.contains(index) == true else { return }
        block.listItems!.remove(at: index)
    }

    // MARK: - Checklist

    private var checklistEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            let items = block.checklistItems ?? []
            ForEach(items.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Button { toggleChecklist(index) } label: {
                        Image(systemName: isChecklistDone(index) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isChecklistDone(index) ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    TextField("Checklist item", text: checklistTextBinding(index))
                    Button { removeChecklistItem(index) } label: {
                        Image(systemName: "minus.circle").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { addChecklistItem() } label: {
                Label("Add item", systemImage: "plus").font(.caption)
            }
        }
    }

    private func isChecklistDone(_ index: Int) -> Bool {
        (block.checklistItems?.indices.contains(index) ?? false) && block.checklistItems![index].isDone
    }

    private func checklistTextBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { (block.checklistItems?.indices.contains(index) ?? false) ? block.checklistItems![index].text : "" },
            set: { newValue in
                guard block.checklistItems?.indices.contains(index) == true else { return }
                block.checklistItems![index].text = newValue
            }
        )
    }

    private func toggleChecklist(_ index: Int) {
        guard block.checklistItems?.indices.contains(index) == true else { return }
        block.checklistItems![index].isDone.toggle()
    }

    private func addChecklistItem() {
        if block.checklistItems == nil { block.checklistItems = [] }
        block.checklistItems!.append(PageChecklistItem())
    }

    private func removeChecklistItem(_ index: Int) {
        guard block.checklistItems?.indices.contains(index) == true else { return }
        block.checklistItems!.remove(at: index)
    }
}

/// Rich-text box backed by the iOS 26 `AttributedString` `TextEditor`
/// (native bold/italic/underline/color), with a placeholder overlay.
struct RichTextBox: View {
    @Binding var text: AttributedString
    var placeholder: String
    var font: Font = .body
    var minHeight: CGFloat = 34

    var body: some View {
        TextEditor(text: $text)
            .font(font)
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .overlay(alignment: .topLeading) {
                if text.characters.isEmpty {
                    Text(placeholder)
                        .font(font)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Editor for `photo` (single) and `photoGrid` (many) blocks.
struct PagePhotoBlockEditor: View {
    @Binding var block: PageBlock
    let project: Project

    @State private var isPicking = false

    private var isGrid: Bool { block.kind == .photoGrid }

    private var photos: [Photo] {
        (block.photoIDs ?? []).compactMap { id in
            project.activePhotos.first { $0.id == id }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if photos.isEmpty {
                Button { isPicking = true } label: {
                    HStack {
                        Image(systemName: isGrid ? "square.grid.2x2" : "photo")
                        Text(isGrid ? "Add Photos" : "Add Photo")
                    }
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else {
                photoPreview
                controlsRow
            }
            TextField("Caption (optional)", text: captionBinding)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $isPicking) {
            ProjectPhotoPickerSheet(
                project: project,
                excludedIDs: Set(block.photoIDs ?? []),
                singleSelection: !isGrid,
                onPick: { picked in
                    if isGrid {
                        block.photoIDs = (block.photoIDs ?? []) + picked.map(\.id)
                    } else {
                        block.photoIDs = picked.first.map { [$0.id] } ?? []
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var photoPreview: some View {
        if isGrid {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: block.columns ?? 2)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(photos) { photo in
                    thumbnail(photo)
                }
            }
        } else if let photo = photos.first {
            thumbnail(photo)
                .frame(maxWidth: 200)
        }
    }

    private func thumbnail(_ photo: Photo) -> some View {
        PhotoCell(photo: photo)
            .frame(height: isGrid ? nil : 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                Button { removePhoto(photo.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .padding(4)
            }
    }

    private var controlsRow: some View {
        HStack(spacing: 12) {
            if isGrid {
                Menu {
                    Picker("Columns", selection: columnsBinding) {
                        Text("2 columns").tag(2)
                        Text("3 columns").tag(3)
                    }
                } label: {
                    Label("^[\(block.columns ?? 2) column](inflect: true)", systemImage: "square.grid.2x2")
                }
                Button { isPicking = true } label: {
                    Label("Add Photos", systemImage: "plus")
                }
            } else {
                Menu {
                    Picker("Size", selection: sizeBinding) {
                        ForEach(PagePhotoSize.allCases, id: \.self) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    Toggle("Square crop", isOn: squareBinding)
                } label: {
                    Label((block.photoSize ?? .full).label, systemImage: "aspectratio")
                }
                Button { isPicking = true } label: {
                    Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            Spacer()
        }
        .font(.caption)
    }

    // MARK: - Bindings & mutations

    private var captionBinding: Binding<String> {
        Binding(
            get: { block.caption ?? "" },
            set: { block.caption = $0.isEmpty ? nil : $0 }
        )
    }

    private var columnsBinding: Binding<Int> {
        Binding(get: { block.columns ?? 2 }, set: { block.columns = $0 })
    }

    private var sizeBinding: Binding<PagePhotoSize> {
        Binding(get: { block.photoSize ?? .full }, set: { block.photoSize = $0 })
    }

    private var squareBinding: Binding<Bool> {
        Binding(get: { block.squareCrop ?? false }, set: { block.squareCrop = $0 })
    }

    private func removePhoto(_ id: UUID) {
        block.photoIDs?.removeAll { $0 == id }
    }
}
