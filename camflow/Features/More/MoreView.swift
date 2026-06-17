import SwiftUI
import SwiftData

struct MoreView: View {
    @Environment(Session.self) private var session
    @Environment(AppServices.self) private var services
    @State private var isConfirmingSignOut = false

    private var syncStatusText: String {
        guard services.networkMonitor.isOnline else { return String(localized: "Offline") }
        switch services.syncEngine.state {
        case .idle: return String(localized: "Up to date")
        case .syncing: return String(localized: "Syncing…")
        case .offline: return String(localized: "Offline")
        case .error: return String(localized: "Sync failed")
        }
    }

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
                    Button {
                        services.syncNow()
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(services.syncEngine.state == .syncing || !services.networkMonitor.isOnline)
                    LabeledContent("Status") { Text(syncStatusText) }
                    if let last = services.syncEngine.lastSyncedAt {
                        LabeledContent("Last Synced") {
                            Text(last, format: .relative(presentation: .named))
                        }
                    }
                } header: {
                    Text("Sync")
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
                    // Revoke the session server-side, wipe the local store, and
                    // route back to auth (cloud is the source of truth on re-login).
                    Task { await services.signOut() }
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
    let session = Session(context: container.mainContext)
    return MoreView()
        .modelContainer(container)
        .environment(session)
        .environment(AppServices(modelContext: container.mainContext, session: session))
}
