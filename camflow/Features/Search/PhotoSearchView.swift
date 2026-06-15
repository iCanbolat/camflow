import SwiftUI
import SwiftData

/// Organization-wide search over photos and videos. Matches the query against
/// tags, project name/address, the uploader's name, and the caption. Results
/// show in a date-sorted grid; tapping opens the photo viewer.
struct PhotoSearchView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Photo> { $0.deletedAt == nil }, sort: \Photo.capturedAt, order: .reverse)
    private var allPhotos: [Photo]

    @State private var searchText = ""
    @State private var scope: MediaScope = .all
    /// Drives `.searchable`; flipped on so the field is focused (keyboard up)
    /// the moment the sheet opens from Home's search button.
    @State private var isSearchActive = false

    /// `initialQuery` exists so the `-debugScreen search` harness can land on a
    /// populated result grid; production callers use the no-argument form.
    init(initialQuery: String = "") {
        _searchText = State(initialValue: initialQuery)
    }

    enum MediaScope: String, CaseIterable, Identifiable {
        case all, photos, videos
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .all: "All"
            case .photos: "Photos"
            case .videos: "Videos"
            }
        }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    /// Trimmed query; an empty query shows the start screen rather than results.
    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Data

    private var orgPhotos: [Photo] {
        allPhotos.filter { $0.project?.organization?.id == session.activeOrganizationID }
    }

    private var scopedPhotos: [Photo] {
        switch scope {
        case .all: orgPhotos
        case .photos: orgPhotos.filter { !$0.isVideo }
        case .videos: orgPhotos.filter { $0.isVideo }
        }
    }

    private var results: [Photo] {
        guard !query.isEmpty else { return [] }
        return scopedPhotos.filter { photo in
            photo.caption.localizedStandardContains(query)
                || (photo.project?.name.localizedStandardContains(query) ?? false)
                || (photo.project?.address.localizedStandardContains(query) ?? false)
                || (photo.author?.name.localizedStandardContains(query) ?? false)
                || photo.tags.contains { $0.deletedAt == nil && $0.name.localizedStandardContains(query) }
        }
    }

    /// Distinct active tags that appear on the active org's photos — quick filters.
    private var suggestedTags: [Tag] {
        var seen = Set<UUID>()
        var out: [Tag] = []
        for photo in orgPhotos {
            for tag in photo.tags where tag.deletedAt == nil && seen.insert(tag.id).inserted {
                out.append(tag)
            }
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    searchStartView
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    resultsGrid
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .searchable(text: $searchText, isPresented: $isSearchActive, prompt: Text("Tags, projects, location, people"))
            .searchScopes($scope) {
                ForEach(MediaScope.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .navigationDestination(for: Photo.self) { photo in
                PhotoViewerView(
                    photos: results,
                    initialIndex: results.firstIndex { $0.id == photo.id } ?? 0
                )
            }
            .task {
                // Auto-focus on entry; skip when a query was injected (debug harness).
                if searchText.isEmpty { isSearchActive = true }
            }
        }
    }

    // MARK: - Subviews

    private var resultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(results) { photo in
                    NavigationLink(value: photo) {
                        PhotoCell(photo: photo)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var searchStartView: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Search your organization")
                        .font(.headline)
                    Text("Find photos and videos by tag, project, location, or who uploaded them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                .padding(.horizontal, 32)

                if !suggestedTags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Browse by tag")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestedTags) { tag in
                                    Button {
                                        searchText = tag.name
                                    } label: {
                                        LabelChip(name: tag.name, colorHex: tag.colorHex)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }
}
