import SwiftUI
import SwiftData
import PhotosUI

/// Edits the active organization's branding (logo/name/contact) used on report
/// covers and photo watermarks.
struct CompanyProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @Environment(\.dismiss) private var dismiss

    @State private var organization: Organization?
    @State private var logoItem: PhotosPickerItem?
    @State private var logoImage: UIImage?
    @State private var isConfirmingDelete = false

    var body: some View {
        Form {
            if let organization {
                @Bindable var organization = organization

                Section("Logo") {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $logoItem, matching: .images) {
                            Group {
                                if let logoImage {
                                    Image(uiImage: logoImage)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.title)
                                        Text("Add Logo")
                                            .font(.caption)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 100, height: 100)
                            .background(.fill.tertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                        Spacer()
                    }
                    if logoImage != nil {
                        Button("Remove Logo", role: .destructive) {
                            removeLogo()
                        }
                    }
                }

                Section("Company") {
                    TextField("Company name", text: $organization.name)
                    PhoneNumberField("Phone", text: $organization.phone)
                    TextField("Email", text: $organization.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Website", text: $organization.website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }

                if session.can(.deleteOrganization) {
                    Section {
                        Button("Delete Organization", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    } footer: {
                        Text("Removes the organization, its projects, photos, and team for everyone.")
                    }
                }
            }
        }
        .navigationTitle("Company Profile")
        .confirmationDialog(
            "Delete \(organization?.name ?? "this organization")?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Organization", role: .destructive) {
                deleteOrganization()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the organization, its projects, photos, and team for everyone. This cannot be undone.")
        }
        .onAppear(perform: load)
        .onChange(of: logoItem) {
            Task { await importLogo() }
        }
        .onDisappear {
            if let organization, organization.deletedAt == nil {
                OrganizationStore(context: modelContext).touch(organization)
            }
        }
    }

    private func deleteOrganization() {
        guard let organization else { return }
        OrganizationStore(context: modelContext).softDelete(organization)
        session.handleOrgDeleted()
        dismiss()
    }

    private func load() {
        let loaded = session.activeOrganization
        organization = loaded
        if let fileName = loaded?.logoFileName {
            logoImage = FileStorage.loadImage(fileName, in: .branding)
        }
    }

    private func importLogo() async {
        guard let data = try? await logoItem?.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let organization else { return }
        let fileName = "logo-\(organization.id.uuidString).png"
        if let png = image.pngData() {
            _ = try? FileStorage.save(png, named: fileName, in: .branding)
            organization.logoFileName = fileName
            logoImage = image
        }
    }

    private func removeLogo() {
        guard let organization, let fileName = organization.logoFileName else { return }
        FileStorage.delete(fileName, in: .branding)
        organization.logoFileName = nil
        logoImage = nil
        logoItem = nil
    }
}
