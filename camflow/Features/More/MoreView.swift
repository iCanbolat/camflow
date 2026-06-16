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

                if session.can(.editCompanyProfile) || session.can(.manageBilling) {
                    Section {
                        if session.can(.editCompanyProfile) {
                            NavigationLink {
                                CompanyProfileView()
                            } label: {
                                Label("Company Profile", systemImage: "building.2.fill")
                            }
                        }
                        if session.can(.manageBilling) {
                            NavigationLink {
                                PlanBillingView()
                            } label: {
                                HStack {
                                    Label("Plan & Billing", systemImage: "creditcard.fill")
                                    Spacer()
                                    Text(session.activePlan.displayName)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if session.can(.manageTaxonomy) {
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
                }

                Section("Preferences") {
                    NavigationLink {
                        StorageView()
                    } label: {
                        HStack {
                            Label("Storage", systemImage: "internaldrive.fill")
                            Spacer()
                            Text(session.activeStorageLimit, format: .byteCount(style: .file))
                                .foregroundStyle(.secondary)
                        }
                    }
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
