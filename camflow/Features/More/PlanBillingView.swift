import SwiftUI
import SwiftData

/// Plan & Billing (More tab, owner/admin only). Local mock: switching tiers is
/// instant and free; real payment flows arrive with cloud accounts.
struct PlanBillingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @State private var pendingTier: PlanTier?

    var body: some View {
        Form {
            if let org = session.activeOrganization {
                currentPlanSection(org)
                ForEach(PlanTier.allCases, id: \.self) { tier in
                    tierSection(tier, org: org)
                }
            }
        }
        .navigationTitle("Plan & Billing")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Switch to \(pendingTier?.displayName ?? "")?",
            isPresented: Binding(get: { pendingTier != nil }, set: { if !$0 { pendingTier = nil } }),
            titleVisibility: .visible
        ) {
            Button("Switch Plan") {
                if let tier = pendingTier, let org = session.activeOrganization {
                    OrganizationStore(context: modelContext).setPlan(tier, for: org)
                }
                pendingTier = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let tier = pendingTier, let org = session.activeOrganization,
               let warning = downgradeWarning(to: tier, org: org) {
                Text(warning)
            }
        }
    }

    private func currentPlanSection(_ org: Organization) -> some View {
        Section {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(org.name)
                        .font(.headline)
                    Text(org.planTier.tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                LabelChip(name: org.planTier.displayName, colorHex: org.planTier.chipColorHex)
            }
            usageRow(
                label: String(localized: "Projects"),
                count: org.activeProjects.count,
                limit: org.planTier.maxActiveProjects
            )
            usageRow(
                label: String(localized: "Members"),
                count: org.activeMembers.count,
                limit: org.planTier.maxMembers
            )
        } header: {
            Text("Current Plan")
        } footer: {
            Text("Real payments arrive with cloud accounts — plan changes are instant and free today.")
        }
    }

    private func usageRow(label: String, count: Int, limit: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(label) {
                if let limit {
                    Text(verbatim: "\(count)/\(limit)")
                } else {
                    Text("\(count) · Unlimited")
                }
            }
            if let limit {
                ProgressView(value: Double(min(count, limit)), total: Double(limit))
                    .tint(count >= limit ? .orange : .accentColor)
            }
        }
    }

    private func tierSection(_ tier: PlanTier, org: Organization) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tier.displayName)
                        .font(.headline)
                    Spacer()
                    if tier == org.planTier {
                        LabelChip(name: String(localized: "Current"), colorHex: tier.chipColorHex)
                    }
                }
                ForEach(tier.featureBullets, id: \.self) { bullet in
                    Label(bullet, systemImage: "checkmark")
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 4)

            Button {
                pendingTier = tier
            } label: {
                Text(tier == org.planTier ? "Current Plan" : "Switch to \(tier.displayName)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: tier.chipColorHex))
            .disabled(tier == org.planTier)
        }
    }

    /// Switching below current usage is allowed — nothing is deleted, new
    /// creation is just blocked — but the user should know that up front.
    private func downgradeWarning(to tier: PlanTier, org: Organization) -> String? {
        var lines: [String] = []
        if let limit = tier.maxActiveProjects, org.activeProjects.count > limit {
            lines.append(String(localized: "You have \(org.activeProjects.count) active projects; \(tier.displayName) allows \(limit). Existing projects stay, but creating new ones is blocked until you're under the limit."))
        }
        if let limit = tier.maxMembers, org.activeMembers.count > limit {
            lines.append(String(localized: "Your team has \(org.activeMembers.count) members; \(tier.displayName) allows \(limit). Existing members stay, but inviting is blocked until you're under the limit."))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Organization.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return NavigationStack { PlanBillingView() }
        .modelContainer(container)
        .environment(Session(context: container.mainContext))
}
