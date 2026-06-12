import SwiftUI
import SwiftData
import MapKit
import ARKit

struct ProjectDetailView: View {
    private enum Segment: String, CaseIterable {
        case photos = "Photos"
        case tasks = "Tasks"
        case reports = "Reports"
        case info = "Info"
    }

    @Bindable var project: Project

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @Query(filter: #Predicate<Tag> { $0.deletedAt == nil }, sort: \Tag.name)
    private var tags: [Tag]

    @State private var segment: Segment = .photos
    @State private var isShowingEditor = false
    @State private var isConfirmingDelete = false
    @State private var upgradeContext: UpgradeContext?

    // Photo grid state
    @State private var filterTagID: UUID?
    @State private var isSelecting = false
    @State private var selectedPhotoIDs: Set<UUID> = []
    @State private var isShowingShareSheet = false
    @State private var isShowingTagPicker = false
    @State private var isConfirmingPhotoDelete = false
    @State private var isShowingMemberPicker = false
    @State private var editingBeforeAfterPair: BeforeAfterPair?
    @State private var isCreatingBeforeAfter = false
    @State private var isCreatingMeasurement = false
    @State private var viewingMeasurement: Measurement?

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("Section", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { segment in
                    Text(LocalizedStringKey(segment.rawValue)).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            switch segment {
            case .photos:
                photosSegment
            case .tasks:
                TasksSegmentView(project: project)
            case .reports:
                ReportsSegmentView(project: project)
            case .info:
                infoSegment
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if segment == .photos && !sortedPhotos.isEmpty {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !tags.isEmpty {
                        filterMenu
                    }
                    Button(isSelecting ? "Done" : "Select") {
                        isSelecting.toggle()
                        if !isSelecting {
                            selectedPhotoIDs.removeAll()
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isShowingEditor = true
                    } label: {
                        Label("Edit Project", systemImage: "pencil")
                    }
                    if session.can(.deleteProject) {
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Delete Project", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if segment == .photos && isSelecting {
                selectionActionBar
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            ProjectEditorView(project: project)
        }
        .sheet(isPresented: $isShowingShareSheet) {
            ShareOptionsSheet(photos: selectedPhotos)
        }
        .sheet(isPresented: $isShowingTagPicker) {
            TagPickerSheet(photos: selectedPhotos)
        }
        .sheet(isPresented: $isShowingMemberPicker) {
            MemberPickerSheet(project: project)
        }
        .navigationDestination(for: Photo.self) { photo in
            let photos = filteredPhotos
            PhotoViewerView(
                photos: photos,
                initialIndex: photos.firstIndex { $0.id == photo.id } ?? 0
            )
        }
        .confirmationDialog(
            "Delete this project?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                ProjectStore(context: modelContext).softDelete(project)
                dismiss()
            }
        } message: {
            Text("The project and its photos will be removed from your library.")
        }
        .confirmationDialog(
            "Delete ^[\(selectedPhotoIDs.count) item](inflect: true)?",
            isPresented: $isConfirmingPhotoDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let store = PhotoStore(context: modelContext)
                for photo in selectedPhotos {
                    store.softDelete(photo)
                }
                selectedPhotoIDs.removeAll()
                isSelecting = false
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let label = project.label {
                    LabelChip(name: label.name, colorHex: label.colorHex)
                }
                if !project.address.isEmpty {
                    Text(project.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Photos

    private var sortedPhotos: [Photo] {
        project.activePhotos.sorted { $0.capturedAt > $1.capturedAt }
    }

    private var filteredPhotos: [Photo] {
        guard let filterTagID else { return sortedPhotos }
        return sortedPhotos.filter { photo in
            photo.tags.contains { $0.id == filterTagID }
        }
    }

    private var selectedPhotos: [Photo] {
        filteredPhotos.filter { selectedPhotoIDs.contains($0.id) }
    }

    private var photoSections: [(day: Date, photos: [Photo])] {
        let groups = Dictionary(grouping: filteredPhotos) {
            Calendar.current.startOfDay(for: $0.capturedAt)
        }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }

    @ViewBuilder
    private var photosSegment: some View {
        if sortedPhotos.isEmpty {
            placeholderSegment(
                title: "No Photos Yet",
                systemImage: "camera",
                message: "Photos you capture for this project will appear here."
            )
        } else if filteredPhotos.isEmpty {
            ContentUnavailableView {
                Label("No Matching Photos", systemImage: "tag.slash")
            } description: {
                Text("No photos carry the selected tag.")
            } actions: {
                Button("Clear Filter") { filterTagID = nil }
            }
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
                    spacing: 2,
                    pinnedViews: [.sectionHeaders]
                ) {
                    ForEach(photoSections, id: \.day) { section in
                        Section {
                            ForEach(section.photos) { photo in
                                photoCell(photo)
                            }
                        } header: {
                            dayHeader(section.day, count: section.photos.count)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func photoCell(_ photo: Photo) -> some View {
        if isSelecting {
            PhotoCell(photo: photo)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: selectedPhotoIDs.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .tint)
                        .shadow(radius: 2)
                        .padding(6)
                }
                .opacity(selectedPhotoIDs.contains(photo.id) ? 0.7 : 1)
                .onTapGesture {
                    if selectedPhotoIDs.contains(photo.id) {
                        selectedPhotoIDs.remove(photo.id)
                    } else {
                        selectedPhotoIDs.insert(photo.id)
                    }
                }
        } else {
            NavigationLink(value: photo) {
                PhotoCell(photo: photo)
            }
        }
    }

    private func dayHeader(_ day: Date, count: Int) -> some View {
        HStack {
            Text(day.dayGroupTitle)
                .font(.subheadline.weight(.semibold))
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Filter by tag", selection: $filterTagID) {
                Text("All Photos").tag(UUID?.none)
                ForEach(tags) { tag in
                    Text(tag.name).tag(Optional(tag.id))
                }
            }
        } label: {
            Image(systemName: filterTagID == nil ? "tag" : "tag.fill")
        }
    }

    private var selectionActionBar: some View {
        HStack(spacing: 24) {
            Button {
                isShowingShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
            }
            Button {
                isShowingTagPicker = true
            } label: {
                Image(systemName: "tag")
                    .font(.title3)
            }

            Spacer()

            Text("^[\(selectedPhotoIDs.count) item](inflect: true) selected")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive) {
                isConfirmingPhotoDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.title3)
            }
        }
        .disabled(selectedPhotoIDs.isEmpty)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Info

    private var infoSegment: some View {
        Form {
            if project.hasCoordinate {
                Section {
                    let coordinate = CLLocationCoordinate2D(
                        latitude: project.latitude!,
                        longitude: project.longitude!
                    )
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coordinate,
                        latitudinalMeters: 600,
                        longitudinalMeters: 600
                    ))) {
                        Marker(project.name, coordinate: coordinate)
                    }
                    .frame(height: 160)
                    .allowsHitTesting(false)
                    .listRowInsets(EdgeInsets())
                }
            }

            Section("Details") {
                if !project.address.isEmpty {
                    LabeledContent("Address", value: project.address)
                }
                LabeledContent("Created") {
                    Text(project.createdAt, format: .dateTime.day().month().year())
                }
                LabeledContent("Photos", value: "\(project.activePhotos.count)")
            }

            Section("Team") {
                if project.activeMembers.isEmpty {
                    Text("No members on this project yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(project.activeMembers) { member in
                        HStack(spacing: 12) {
                            MemberAvatar(member: member, size: 32)
                            Text(member.name)
                            Spacer()
                            if !member.title.isEmpty {
                                Text(member.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if session.can(.manageTeam) {
                    Button {
                        isShowingMemberPicker = true
                    } label: {
                        Label("Manage Members", systemImage: "person.badge.plus")
                    }
                }
            }

            beforeAfterSection

            measurementsSection

            Section("Notes") {
                TextEditor(text: $project.notes)
                    .frame(minHeight: 100)
            }
        }
        .sheet(isPresented: $isCreatingBeforeAfter) {
            BeforeAfterComposerView(project: project)
        }
        .sheet(item: $editingBeforeAfterPair) { pair in
            BeforeAfterComposerView(project: project, existingPair: pair)
        }
        .sheet(item: $viewingMeasurement) { measurement in
            MeasurementDetailSheet(measurement: measurement)
        }
        .sheet(item: $upgradeContext) { context in
            UpgradePromptSheet(context: context)
        }
        .fullScreenCover(isPresented: $isCreatingMeasurement) {
            MeasureView(project: project)
        }
        .onDisappear {
            ProjectStore(context: modelContext).touch(project)
        }
    }

    private var activeBeforeAfterPairs: [BeforeAfterPair] {
        project.beforeAfterPairs
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var beforeAfterSection: some View {
        Section("Before & After") {
            ForEach(activeBeforeAfterPairs) { pair in
                Button {
                    editingBeforeAfterPair = pair
                } label: {
                    HStack(spacing: 8) {
                        pairThumbnail(photoID: pair.beforePhotoID)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        pairThumbnail(photoID: pair.afterPhotoID)
                        Spacer()
                        Text(pair.createdAt, format: .dateTime.day().month())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                let store = BeforeAfterStore(context: modelContext)
                for offset in offsets {
                    store.softDelete(activeBeforeAfterPairs[offset])
                }
            }

            Button {
                isCreatingBeforeAfter = true
            } label: {
                Label("New Before / After", systemImage: "rectangle.split.2x1")
            }
            .disabled(project.activePhotos.filter { !$0.isVideo }.count < 2)
        }
    }

    private var sortedMeasurements: [Measurement] {
        project.activeMeasurements.sorted { $0.capturedAt > $1.capturedAt }
    }

    private var measurementsSection: some View {
        Section {
            ForEach(sortedMeasurements) { measurement in
                Button {
                    viewingMeasurement = measurement
                } label: {
                    HStack {
                        Image(systemName: "ruler")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Measurement.format(meters: measurement.totalMeters, in: measurement.unit))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.primary)
                            Text("^[\(measurement.segments.count) segment](inflect: true)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(measurement.capturedAt, format: .dateTime.day().month())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                let store = MeasurementStore(context: modelContext)
                for offset in offsets {
                    store.softDelete(sortedMeasurements[offset])
                }
            }

            // Plan lock comes before device support: a locked button stays
            // tappable so it can present the upsell sheet.
            if session.activePlan.includesARMeasure {
                Button {
                    isCreatingMeasurement = true
                } label: {
                    Label("New Measurement", systemImage: "ruler")
                }
                .disabled(!ARWorldTrackingConfiguration.isSupported)
            } else {
                Button {
                    upgradeContext = .arMeasure
                } label: {
                    HStack {
                        Label("New Measurement", systemImage: "ruler")
                        Spacer()
                        LockBadge()
                    }
                }
            }
        } header: {
            Text("Measurements")
        } footer: {
            if !session.activePlan.includesARMeasure {
                Text("AR measurement is included with the Premium plan.")
            } else if !ARWorldTrackingConfiguration.isSupported {
                Text("AR measuring isn't supported on this device.")
            }
        }
    }

    @ViewBuilder
    private func pairThumbnail(photoID: UUID) -> some View {
        if let photo = project.activePhotos.first(where: { $0.id == photoID }) {
            PhotoCell(photo: photo)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.fill.tertiary)
                .frame(width: 44, height: 44)
        }
    }

    private func placeholderSegment(
        title: LocalizedStringKey,
        systemImage: String,
        message: LocalizedStringKey
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
        .frame(maxHeight: .infinity)
    }
}
