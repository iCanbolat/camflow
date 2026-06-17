import SwiftUI

/// Blocking gate shown when an owner's organization trial has ended
/// (`Session.requiresSubscription`). The owner must choose a paid plan to
/// continue — local mock: subscribing is instant and free; real payments arrive
/// with cloud accounts. Only ever shown to the org owner, so there's no
/// "ask your admin" branch (unlike `UpgradePromptSheet`).
struct PaywallView: View {
    @Environment(Session.self) private var session
    @Environment(AppServices.self) private var services

    @State private var pendingTier: PlanTier?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                VStack(spacing: 16) {
                    ForEach(PlanTier.allCases, id: \.self, content: tierCard)
                }
                footer
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .confirmationDialog(
            "Subscribe to \(pendingTier?.displayName ?? "")?",
            isPresented: Binding(get: { pendingTier != nil }, set: { if !$0 { pendingTier = nil } }),
            titleVisibility: .visible
        ) {
            Button("Subscribe") {
                if let tier = pendingTier { session.subscribe(tier) }
                pendingTier = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let tier = pendingTier {
                Text(verbatim: "\(tier.displayName) — \(tier.price) \(tier.pricePeriod)")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .padding(.top, 24)
            Text("Your free trial has ended")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("Choose a plan to keep using CamFlow. Your projects and data are safe.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
    }

    private func tierCard(_ tier: PlanTier) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(tier.displayName)
                    .font(.title3.bold())
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(tier.price)
                        .font(.title3.bold())
                    Text(tier.pricePeriod)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(tier.featureBullets, id: \.self) { bullet in
                    Label(bullet, systemImage: "checkmark")
                        .font(.subheadline)
                }
            }

            Button {
                pendingTier = tier
            } label: {
                Text("Choose \(tier.displayName)")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: tier.chipColorHex))
            .padding(.top, 4)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button("Sign Out", role: .destructive) {
                Task { await services.signOut() }
            }
            .font(.subheadline)

            Text("Real payments arrive with cloud accounts — subscriptions are instant and free today.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }
}
