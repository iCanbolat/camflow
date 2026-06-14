import SwiftUI
import SwiftData
import PhotosUI

/// Captures an organization's name + logo and creates it owned by the current
/// account. Used both as the post-signup onboarding step and from the Home
/// switcher's "Create Organization" action.
struct CreateOrganizationView: View {
    /// When presented as a sheet (from the switcher) this dismisses it.
    var isModal = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session

    @State private var name = ""
    @State private var logoItem: PhotosPickerItem?
    @State private var logoImage: UIImage?
    @State private var isShowingCodeEntry = false
    @State private var clipboardCode: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(spacing: 32) {
            if isModal {
                Spacer().frame(height: 8)
            } else {
                Spacer()
            }

            VStack(spacing: 12) {
                Text("Create Organization")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Your company workspace — projects, team, and branding live here. You can create more later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 20) {
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
                    .frame(width: 120, height: 120)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                }

                AuthInputRow(icon: "building.2") {
                    TextField("Organization name", text: $name)
                        .font(.title3)
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: create) {
                    Text("Create")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(trimmedName.isEmpty)

                if !isModal {
                    Button("Have an invite code?") { isShowingCodeEntry = true }
                        .font(.footnote.weight(.medium))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            if isModal {
                Button("Cancel") { dismiss() }
                    .padding()
            }
        }
        .sheet(isPresented: $isShowingCodeEntry) {
            InviteCodeEntrySheet()
        }
        .task {
            // Onboarding step only; InviteClipboard's once-per-launch flag
            // also keeps this from double-prompting after AuthView.
            guard !isModal, session.pendingInviteCode == nil else { return }
            clipboardCode = await InviteClipboard.detectInviteCode()
        }
        .alert(
            "Join with invite code \(clipboardCode ?? "")?",
            isPresented: Binding(get: { clipboardCode != nil }, set: { if !$0 { clipboardCode = nil } })
        ) {
            Button("Join") {
                session.setPendingInvite(code: clipboardCode)
                clipboardCode = nil
            }
            Button("Not Now", role: .cancel) { clipboardCode = nil }
        } message: {
            Text("We found a CamFlow invite link on your clipboard.")
        }
        .onChange(of: logoItem) {
            Task {
                if let data = try? await logoItem?.loadTransferable(type: Data.self) {
                    logoImage = UIImage(data: data)
                }
            }
        }
    }

    private func create() {
        guard let account = session.currentAccount else { return }
        let store = OrganizationStore(context: modelContext)
        // One owned org per user: if they already own one, just activate it.
        if let existing = store.ownedOrganization(for: account) {
            session.setActiveOrg(existing)
            if isModal { dismiss() }
            return
        }
        let org = store.create(name: trimmedName, owner: account)

        if let logoImage, let data = logoImage.pngData() {
            let fileName = "logo-\(org.id.uuidString).png"
            _ = try? FileStorage.save(data, named: fileName, in: .branding)
            org.logoFileName = fileName
        }
        store.touch(org)
        session.setActiveOrg(org)

        if isModal {
            dismiss()
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Account.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return CreateOrganizationView()
        .modelContainer(container)
        .environment(Session(context: container.mainContext))
}
