import SwiftUI

/// Picks photos from a project's library (e.g. task evidence, checklist
/// item proof). Single-select mode returns immediately on tap.
struct ProjectPhotoPickerSheet: View {
    let project: Project
    var excludedIDs: Set<UUID> = []
    var singleSelection = false
    /// Photo-only consumers (e.g. before/after pairs) can't use videos;
    /// task/checklist evidence accepts them.
    var excludesVideos = false
    let onPick: ([Photo]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedIDs: Set<UUID> = []

    private var photos: [Photo] {
        project.activePhotos
            .filter { !excludedIDs.contains($0.id) && !(excludesVideos && $0.isVideo) }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if photos.isEmpty {
                    ContentUnavailableView {
                        Label("No Photos Available", systemImage: "photo")
                    } description: {
                        Text("Capture photos for this project first.")
                    }
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
                            spacing: 2
                        ) {
                            ForEach(photos) { photo in
                                PhotoCell(photo: photo)
                                    .overlay(alignment: .bottomTrailing) {
                                        if !singleSelection {
                                            Image(systemName: selectedIDs.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, .tint)
                                                .shadow(radius: 2)
                                                .padding(6)
                                        }
                                    }
                                    .onTapGesture {
                                        handleTap(photo)
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle(singleSelection ? "Pick a Photo" : "Pick Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !singleSelection {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            onPick(photos.filter { selectedIDs.contains($0.id) })
                            dismiss()
                        }
                        .disabled(selectedIDs.isEmpty)
                    }
                }
            }
        }
    }

    private func handleTap(_ photo: Photo) {
        if singleSelection {
            onPick([photo])
            dismiss()
        } else if selectedIDs.contains(photo.id) {
            selectedIDs.remove(photo.id)
        } else {
            selectedIDs.insert(photo.id)
        }
    }
}
