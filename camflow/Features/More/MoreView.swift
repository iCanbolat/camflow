import SwiftUI
import SwiftData

struct MoreView: View {
    @Environment(Session.self) private var session
    @State private var isConfirmingSignOut = false

    var body: some View {
        NavigationStack {
            List {
                if let account = session.currentAccount {
                    Section {
                        HStack(spacing: 12) {
                            AccountAvatar(account: account, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.displayName)
                                    .font(.headline)
                                Text(account.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        CompanyProfileView()
                    } label: {
                        Label("Company Profile", systemImage: "building.2.fill")
                    }
                }

                Section("Organization") {
                    NavigationLink {
                        TagManagerView()
                    } label: {
                        Label("Photo Tags", systemImage: "tag.fill")
                    }
                    NavigationLink {
                        LabelManagerView()
                    } label: {
                        Label("Project Labels", systemImage: "flag.fill")
                    }
                    NavigationLink {
                        TemplateListView()
                    } label: {
                        Label("Checklist Templates", systemImage: "list.bullet.rectangle.fill")
                    }
                }

                Section("Preferences") {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                }

                Section {
                    LabeledContent("Version") {
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        isConfirmingSignOut = true
                    }
                }
            }
            .navigationTitle("More")
            .confirmationDialog("Sign out of CamFlow?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    // Re-prime permissions only after the next sign-in completes
                    // so a different account still sees the gate if needed.
                    session.signOut()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

/// Circular initials avatar for an `Account`.
struct AccountAvatar: View {
    let account: Account
    var size: CGFloat = 32

    var body: some View {
        Text(account.initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: account.colorHex), in: Circle())
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Account.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return MoreView()
        .modelContainer(container)
        .environment(Session(context: container.mainContext))
}
