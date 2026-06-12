import SwiftUI
import SwiftData

/// Applies tags to one or more photos. A tag shows checked when every
/// target photo carries it; tapping toggles it on/off for all of them.
struct TagPickerSheet: View {
    let photos: [Photo]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var tags: [Tag]

    @State private var isCreatingTag = false

    var body: some View {
        NavigationStack {
            Group {
                if tags.isEmpty {
                    ContentUnavailableView {
                        Label("No Tags Yet", systemImage: "tag")
                    } description: {
                        Text("Create tags like “Electrical” or “Damage” to categorize photos.")
                    } actions: {
                        Button("New Tag") { isCreatingTag = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(tags) { tag in
                        Button {
                            toggle(tag)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(hex: tag.colorHex))
                                    .frame(width: 14, height: 14)
                                Text(tag.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isApplied(tag) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(photos.count == 1 ? "Tags" : "Tag \(photos.count) Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreatingTag = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isCreatingTag) {
                NameColorEditorSheet(title: "New Tag") { name, colorHex in
                    modelContext.insert(Tag(name: name, colorHex: colorHex))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func isApplied(_ tag: Tag) -> Bool {
        photos.allSatisfy { photo in photo.tags.contains { $0.id == tag.id } }
    }

    private func toggle(_ tag: Tag) {
        let store = PhotoStore(context: modelContext)
        if isApplied(tag) {
            for photo in photos {
                photo.tags.removeAll { $0.id == tag.id }
                store.touch(photo)
            }
        } else {
            for photo in photos where !photo.tags.contains(where: { $0.id == tag.id }) {
                photo.tags.append(tag)
                store.touch(photo)
            }
        }
    }
}
