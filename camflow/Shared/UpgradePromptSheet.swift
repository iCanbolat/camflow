import SwiftUI
import SwiftData

/// Reason a plan-gated action was blocked. Carries the copy and the tiers
/// that unlock it for `UpgradePromptSheet`.
enum UpgradeContext: String, Identifiable {
    case projectLimit
    case memberLimit
    case arMeasure
    case dualCapture
    case tasks
    case checklists
    case comments
    case pages

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .projectLimit: "folder.badge.plus"
        case .memberLimit: "person.badge.plus"
        case .arMeasure: "ruler"
        case .dualCapture: "rectangle.inset.filled.badge.record"
        case .tasks: "checkmark.circle"
        case .checklists: "list.bullet.rectangle"
        case .comments: "bubble.left.and.bubble.right"
        case .pages: "doc.text.image"
        }
    }

    var title: String {
        switch self {
        case .projectLimit: String(localized: "Project Limit Reached")
        case .memberLimit: String(localized: "Member Limit Reached")
        case .arMeasure: String(localized: "Measure with AR")
        case .dualCapture: String(localized: "Record with Both Cameras")
        case .tasks: String(localized: "Assign Tasks")
        case .checklists: String(localized: "Build Checklists")
        case .comments: String(localized: "Comment & Mention")
        case .pages: String(localized: "Create Pages")
        }
    }

    func message(current plan: PlanTier) -> String {
        switch self {
        case .projectLimit:
            if let limit = plan.maxActiveProjects {
                String(localized: "The \(plan.displayName) plan includes up to ^[\(limit) active project](inflect: true). Upgrade for more.")
            } else {
                String(localized: "Upgrade for more active projects.")
            }
        case .memberLimit:
            if let limit = plan.maxMembers {
                String(localized: "The \(plan.displayName) plan includes up to ^[\(limit) team member](inflect: true). Upgrade for a bigger crew.")
            } else {
                String(localized: "Upgrade for a bigger crew.")
            }
        case .arMeasure:
            String(localized: "Point-to-point AR measurement is part of the Premium plan.")
        case .dualCapture:
            String(localized: "Dual camera (PiP) video is part of the Premium plan.")
        case .tasks:
            String(localized: "Task assignment is part of the Pro plan.")
        case .checklists:
            String(localized: "Checklists are part of the Pro plan.")
        case .comments:
            String(localized: "Comments and @mentions are part of the Pro plan.")
        case .pages:
            String(localized: "Pages are part of the Pro plan.")
        }
    }

    func isUnlocked(by tier: PlanTier) -> Bool {
        switch self {
        case .projectLimit: tier.maxActiveProjects == nil
        case .memberLimit: tier.maxMembers == nil
        case .arMeasure: tier.includesARMeasure
        case .dualCapture: tier.includesDualCapture
        case .tasks: tier.includesTasks
        case .checklists: tier.includesChecklists
        case .comments: tier.includesComments
        case .pages: tier.includesPages
        }
    }
}

/// Shown when a plan limit or premium feature blocks an action. Owners/admins
/// can switch plans inline; everyone else is pointed at them. Present via
/// `.sheet(item: $upgradeContext)`.
struct UpgradePromptSheet: View {
    let context: UpgradeContext

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @State private var pendingTier: PlanTier?

    private var upgradeTiers: [PlanTier] {
        PlanTier.allCases.filter { context.isUnlocked(by: $0) && $0 != session.activePlan }
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: context.icon)
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .padding(.top, 28)

            Text(context.title)
                .font(.title3.bold())

            Text(context.message(current: session.activePlan))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if session.can(.manageBilling) {
                VStack(spacing: 10) {
                    ForEach(upgradeTiers, id: \.self) { tier in
                        Button {
                            pendingTier = tier
                        } label: {
                            VStack(spacing: 2) {
                                Text("Switch to \(tier.displayName)")
                                    .font(.headline)
                                Text(tier.tagline)
                                    .font(.caption)
                                    .opacity(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: tier.chipColorHex))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            } else {
                Label("Ask your organization's owner or admin to upgrade.", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }

            Spacer(minLength: 0)

            Text("Real payments arrive with cloud accounts — plan changes are instant and free today.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .presentationDetents([.medium])
        .confirmationDialog(
            "Switch to \(pendingTier?.displayName ?? "")?",
            isPresented: Binding(get: { pendingTier != nil }, set: { if !$0 { pendingTier = nil } }),
            titleVisibility: .visible
        ) {
            Button("Switch Plan") {
                if let tier = pendingTier, let org = session.activeOrganization {
                    OrganizationStore(context: modelContext).setPlan(tier, for: org)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Small lock glyph appended to plan-gated buttons (Dual capture pill,
/// New Measurement row).
struct LockBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
    }
}
