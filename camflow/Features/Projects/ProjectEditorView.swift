import SwiftUI
import SwiftData
import MapKit

/// Create / edit a project: name, address (search or current location), label.
struct ProjectEditorView: View {
    /// nil creates a new project.
    var project: Project?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationService.self) private var locationService
    @Environment(Session.self) private var session

    @Query(filter: #Predicate<ProjectLabel> { $0.deletedAt == nil }, sort: \ProjectLabel.sortOrder)
    private var labels: [ProjectLabel]

    @State private var name = ""
    @State private var address = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var selectedLabelID: UUID?
    @State private var addressSearch = AddressSearchCompleter()
    @State private var isLocating = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Project name", text: $name)
                }

                Section("Location") {
                    TextField("Search address", text: $addressSearch.query)
                        .autocorrectionDisabled()

                    ForEach(addressSearch.results, id: \.self) { completion in
                        Button {
                            select(completion)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .foregroundStyle(.primary)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if !address.isEmpty {
                        Label(address, systemImage: "mappin.and.ellipse")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        useCurrentLocation()
                    } label: {
                        if isLocating {
                            HStack {
                                ProgressView()
                                Text("Locating…")
                            }
                        } else {
                            Label("Use Current Location", systemImage: "location.fill")
                        }
                    }
                    .disabled(isLocating || !locationService.isAuthorized)
                }

                if !labels.isEmpty {
                    Section("Label") {
                        Picker("Label", selection: $selectedLabelID) {
                            Text("None").tag(UUID?.none)
                            ForEach(labels) { label in
                                Text(label.name).tag(Optional(label.id))
                            }
                        }
                    }
                }
            }
            .navigationTitle(project == nil ? "New Project" : "Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private func loadExisting() {
        guard let project else { return }
        name = project.name
        address = project.address
        latitude = project.latitude
        longitude = project.longitude
        selectedLabelID = project.label?.id
    }

    private func select(_ completion: MKLocalSearchCompletion) {
        Task {
            if let resolved = await addressSearch.resolve(completion) {
                address = resolved.address
                latitude = resolved.latitude
                longitude = resolved.longitude
            }
            addressSearch.query = ""
        }
    }

    private func useCurrentLocation() {
        isLocating = true
        Task {
            defer { isLocating = false }
            guard let location = try? await locationService.currentLocation() else { return }
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude
            if let request = MKReverseGeocodingRequest(location: location),
               let item = try? await request.mapItems.first {
                address = item.address?.fullAddress ?? ""
            }
        }
    }

    private func save() {
        let store = ProjectStore(context: modelContext)
        let label = labels.first { $0.id == selectedLabelID }
        if let project {
            project.name = trimmedName
            project.address = address
            project.latitude = latitude
            project.longitude = longitude
            project.label = label
            store.touch(project)
        } else {
            // Entry points show the upgrade prompt before opening the editor;
            // this guard covers any path that skipped that check.
            guard session.activeOrganization?.canAddProject ?? true else {
                dismiss()
                return
            }
            store.create(
                name: trimmedName,
                address: address,
                latitude: latitude,
                longitude: longitude,
                label: label,
                organization: session.activeOrganization
            )
        }
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Project.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ProjectEditorView()
        .modelContainer(container)
        .environment(LocationService())
        .environment(Session(context: container.mainContext))
}
