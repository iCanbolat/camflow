import SwiftUI
import SwiftData
import UIKit

/// Shown by the root coordinator whenever a pending invite code exists:
/// previews the inviting organization, then redeems on Accept. Declining (or
/// resolving an error) clears the code so the coordinator falls through to
/// org creation or the app.
struct JoinOrganizationView: View {
    let code: String

    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @State private var preview: InvitePreview?
    @State private var failure: InviteError?
    @State private var isWorking = false

    private var service: any InviteService { LocalInviteService(context: modelContext) }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            if let failure {
                failureContent(failure)
            } else if let preview {
                previewContent(preview)
            } else {
                ProgressView("Checking invite…")
            }

            Spacer()

            actions
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .task(id: code) { await loadPreview() }
    }

    // MARK: - Content

    private func previewContent(_ preview: InvitePreview) -> some View {
        VStack(spacing: 20) {
            logoView(fileName: preview.organizationLogoFileName)

            VStack(spacing: 12) {
                Text("Join \(preview.organizationName)")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("\(preview.organizationName) invited \(preview.memberName) as \(preview.roleDisplayName).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Text(code)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .kerning(2)
                .foregroundStyle(.secondary)
        }
    }

    private func failureContent(_ failure: InviteError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Can't Join")
                .font(.largeTitle.bold())
            Text(failure.localizedDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    @ViewBuilder
    private func logoView(fileName: String?) -> some View {
        if let fileName, let image = FileStorage.loadImage(fileName, in: .branding) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 120)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24))
        } else {
            Image(systemName: "building.2")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .frame(width: 120, height: 120)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if let failure {
                if case .alreadyMember(let organizationID, let organizationName) = failure {
                    Button {
                        if let organization = OrganizationStore(context: modelContext)
                            .organization(id: organizationID) {
                            session.setActiveOrg(organization)
                        }
                        session.setPendingInvite(code: nil)
                    } label: {
                        Text("Open \(organizationName)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        session.setPendingInvite(code: nil)
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else {
                Button(action: accept) {
                    Group {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text("Accept Invite")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(preview == nil || isWorking)

                Button("Decline") {
                    session.setPendingInvite(code: nil)
                }
                .disabled(isWorking)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Actions

    private func loadPreview() async {
        failure = nil
        preview = nil
        do {
            preview = try await service.preview(code: code)
        } catch let error as InviteError {
            failure = error
        } catch {
            failure = .codeNotFound
        }
    }

    private func accept() {
        guard let account = session.currentAccount, !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let organization = try await service.redeem(code: code, account: account)
                session.setActiveOrg(organization)
                session.setPendingInvite(code: nil)
            } catch let error as InviteError {
                failure = error
            } catch {
                failure = .codeNotFound
            }
        }
    }
}

/// Manual fallback for fresh installs (no deferred deep linking without a
/// backend): typing the code from the invite link/landing page routes into
/// the same pending-invite flow as a tapped link.
struct InviteCodeEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session

    @State private var code = ""

    private var normalized: String? {
        InviteLinks.normalizedCode(code)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("8-character code", text: $code)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .kerning(2)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } footer: {
                    Text("It's in your invite link: camflow.app/invite/CODE")
                }
            }
            .navigationTitle("Enter Invite Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        session.setPendingInvite(code: normalized)
                        dismiss()
                    }
                    .disabled(normalized == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    let container = try! ModelContainer(
        for: OrgMember.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return JoinOrganizationView(code: "CREW2345")
        .modelContainer(container)
        .environment(Session(context: container.mainContext))
}
