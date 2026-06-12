import SwiftUI
import SwiftData
import PhotosUI

/// Edits the active organization's branding (logo/name/contact) used on report
/// covers and photo watermarks.
struct CompanyProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @State private var organization: Organization?
    @State private var logoItem: PhotosPickerItem?
    @State private var logoImage: UIImage?

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
                    TextField("Phone", text: $organization.phone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $organization.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Website", text: $organization.website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }
            }
        }
        .navigationTitle("Company Profile")
        .onAppear(perform: load)
        .onChange(of: logoItem) {
            Task { await importLogo() }
        }
        .onDisappear {
            if let organization {
                OrganizationStore(context: modelContext).touch(organization)
            }
        }
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
