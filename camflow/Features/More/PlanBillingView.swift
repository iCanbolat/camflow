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
            confirmTitle,
            isPresented: Binding(get: { pendingTier != nil }, set: { if !$0 { pendingTier = nil } }),
            titleVisibility: .visible
        ) {
            Button(isSubscribed ? "Switch Plan" : "Subscribe") {
                if let tier = pendingTier {
                    session.subscribe(tier)
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

    private var isSubscribed: Bool { session.activeOrganization?.isSubscribed ?? false }

    private var confirmTitle: String {
        guard let tier = pendingTier else { return "" }
        return isSubscribed
            ? String(localized: "Switch to \(tier.displayName)?")
            : String(localized: "Subscribe to \(tier.displayName)?")
    }

    private func currentPlanSection(_ org: Organization) -> some View {
        Section {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(org.name)
                        .font(.headline)
                    Text(currentStatusText(org))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if org.subscriptionStatus == .trialing {
                    LabelChip(name: String(localized: "Free Trial"), colorHex: "#34C759")
                } else {
                    LabelChip(name: org.planTier.displayName, colorHex: org.planTier.chipColorHex)
                }
            }
            usageRow(
                label: String(localized: "Projects"),
                count: org.activeProjects.count,
                limit: org.effectivePlan.maxActiveProjects
            )
            usageRow(
                label: String(localized: "Members"),
                count: org.activeMembers.count,
                limit: org.effectivePlan.maxMembers
            )
            storageUsageRow(org)
        } header: {
            Text("Current Plan")
        } footer: {
            Text("Real payments arrive with cloud accounts — plan changes are instant and free today.")
        }
    }

    private func currentStatusText(_ org: Organization) -> String {
        switch org.subscriptionStatus {
        case .trialing: String(localized: "Free trial · \(org.trialDaysRemaining) days left")
        case .active: org.planTier.tagline
        case .expired: String(localized: "Trial ended")
        }
    }

    private func storageUsageRow(_ org: Organization) -> some View {
        let used = FileStorage.totalSize(of: .photos)
            + FileStorage.totalSize(of: .reports)
            + FileStorage.totalSize(of: .pages)
        let limit = org.effectiveStorageBytes
        return VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Storage") {
                Text(verbatim: "\(used.formatted(.byteCount(style: .file))) of \(limit.formatted(.byteCount(style: .file)))")
            }
            ProgressView(value: Double(min(used, limit)), total: Double(max(limit, 1)))
                .tint(used >= limit ? .orange : .accentColor)
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
        let isCurrent = org.subscriptionStatus == .active && tier == org.planTier
        return Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tier.displayName)
                        .font(.headline)
                    Spacer()
                    if isCurrent {
                        LabelChip(name: String(localized: "Current"), colorHex: tier.chipColorHex)
                    }
                }
                Text(verbatim: "\(tier.price) \(tier.pricePeriod)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(tier.featureBullets, id: \.self) { bullet in
                    Label(bullet, systemImage: "checkmark")
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 4)

            Button {
                pendingTier = tier
            } label: {
                Text(buttonTitle(for: tier, org: org))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: tier.chipColorHex))
            .disabled(isCurrent)
        }
    }

    private func buttonTitle(for tier: PlanTier, org: Organization) -> String {
        if org.subscriptionStatus == .active {
            return tier == org.planTier
                ? String(localized: "Current Plan")
                : String(localized: "Switch to \(tier.displayName)")
        }
        return String(localized: "Subscribe to \(tier.displayName)")
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
        if !tier.includesTasks {
            lines.append(String(localized: "Tasks, checklists, comments, and Pages aren't part of \(tier.displayName). Existing items stay viewable and editable, but you can't create new ones."))
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
