import Foundation
import SwiftData

/// A company/organization tenant. Owns its own projects, member roster, and
/// branding (logo/name shown on report covers and photo watermarks). A user
/// can belong to several organizations and switch between them; the active one
/// is tracked by `Session`.
@Model
final class Organization {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Logo file inside `FileStorage.brandingDirectory`. Unique per org so logos
    /// don't collide across tenants.
    var logoFileName: String?
    var phone: String
    var email: String
    var website: String
    /// `Account.id` of the owner who created the organization.
    var ownerAccountID: UUID
    // Stored as an optional raw string: lightweight migration leaves existing
    // rows NULL, and SwiftData crashes casting NULL into a non-optional enum.
    private var planTierRaw: String?

    var planTier: PlanTier {
        get { planTierRaw.flatMap(PlanTier.init(rawValue:)) ?? .basic }
        set { planTierRaw = newValue.rawValue }
    }

    /// When the 7-day free trial started — set at creation (= registration for the
    /// owner). Optional so lightweight migration leaves existing rows NULL, which
    /// `subscriptionStatus` treats as grandfathered-active (never locked out).
    var trialStartedAt: Date?
    /// Set when the owner subscribes to a paid plan (mock). nil = not subscribed.
    var subscriptionStartedAt: Date?
    /// Optional storage add-on stacked on the plan's base storage. Optional raw
    /// string for migration safety (NULL → `.none`), mirroring `planTierRaw`.
    private var storageAddOnRaw: String?

    var storageAddOn: StorageAddOn {
        get { storageAddOnRaw.flatMap(StorageAddOn.init(rawValue:)) ?? .none }
        set { storageAddOnRaw = newValue.rawValue }
    }

    @Relationship(inverse: \OrgMember.organization)
    var members: [OrgMember] = []

    @Relationship(inverse: \Project.organization)
    var projects: [Project] = []

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(name: String, ownerAccountID: UUID) {
        self.id = UUID()
        self.name = name
        self.logoFileName = nil
        self.phone = ""
        self.email = ""
        self.website = ""
        self.ownerAccountID = ownerAccountID
        self.planTierRaw = PlanTier.basic.rawValue
        self.trialStartedAt = .now
        self.subscriptionStartedAt = nil
        self.storageAddOnRaw = nil
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }
}

extension Organization {
    var activeMembers: [OrgMember] {
        members.filter { $0.deletedAt == nil }
    }

    var activeProjects: [Project] {
        projects.filter { $0.deletedAt == nil }
    }

    // MARK: - Trial & subscription

    /// 7 days.
    static let trialLength: TimeInterval = 7 * 24 * 60 * 60

    var trialEndsAt: Date? {
        trialStartedAt.map { $0.addingTimeInterval(Self.trialLength) }
    }

    var isSubscribed: Bool { subscriptionStartedAt != nil }

    var subscriptionStatus: SubscriptionStatus {
        if isSubscribed { return .active }
        // No trial start (legacy/grandfathered rows) → treat as active so existing
        // data is never locked behind the paywall.
        guard let end = trialEndsAt else { return .active }
        return .now < end ? .trialing : .expired
    }

    /// Whole days left in the trial (rounded up), or 0 once it's over.
    var trialDaysRemaining: Int {
        guard let end = trialEndsAt, .now < end else { return 0 }
        return (Calendar.current.dateComponents([.day], from: .now, to: end).day ?? 0) + 1
    }

    /// Entitlement consumed by all feature gates. The trial grants full
    /// (Premium) access; a subscribed/expired org uses its chosen `planTier`.
    var effectivePlan: PlanTier {
        switch subscriptionStatus {
        case .trialing: .premium
        case .active, .expired: planTier
        }
    }

    /// Plan base storage + any purchased add-on.
    var effectiveStorageBytes: Int64 {
        effectivePlan.maxStorageBytes + storageAddOn.bytes
    }

    // MARK: - Limits

    /// Plan limits gate creating new items only; existing data is never removed.
    var canAddProject: Bool {
        effectivePlan.maxActiveProjects.map { activeProjects.count < $0 } ?? true
    }

    var canAddMember: Bool {
        effectivePlan.maxMembers.map { activeMembers.count < $0 } ?? true
    }
}
