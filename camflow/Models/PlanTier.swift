import Foundation

/// Subscription tier of an organization. Local-first mock: switching tiers is
/// instant and free; real payment processing arrives with cloud accounts.
enum PlanTier: String, Codable, CaseIterable {
    case basic
    case pro
    case premium

    var displayName: String {
        switch self {
        case .basic: String(localized: "Basic")
        case .pro: String(localized: "Pro")
        case .premium: String(localized: "Premium")
        }
    }

    var tagline: String {
        switch self {
        case .basic: String(localized: "Document every job")
        case .pro: String(localized: "For growing crews")
        case .premium: String(localized: "Every tool on the truck")
        }
    }

    /// nil = unlimited.
    var maxActiveProjects: Int? {
        switch self {
        case .basic: 1
        case .pro: 5
        case .premium: nil
        }
    }

    /// Includes the owner. nil = unlimited.
    var maxMembers: Int? {
        switch self {
        case .basic: 3
        case .pro: 10
        case .premium: 25
        }
    }

    var includesARMeasure: Bool { self == .premium }
    var includesDualCapture: Bool { self == .premium }

    /// Collaboration suite — Pro and Premium only.
    var includesTasks: Bool { self != .basic }
    var includesChecklists: Bool { self != .basic }
    var includesComments: Bool { self != .basic }
    var includesPages: Bool { self != .basic }

    /// Soft, display-only storage cap (decimal GB so `.byteCount(style: .file)`
    /// reads "2 GB"/"50 GB"/"250 GB"). Not hard-enforced yet — see SettingsView.
    var maxStorageBytes: Int64 {
        switch self {
        case .basic: 5_000_000_000
        case .pro: 50_000_000_000
        case .premium: 150_000_000_000
        }
    }

    var storageDisplay: String {
        maxStorageBytes.formatted(.byteCount(style: .file))
    }

    var price: String {
        switch self {
        case .basic: "$13"
        case .pro: "$40"
        case .premium: "$60"
        }
    }

    var pricePeriod: String { String(localized: "per user / month") }

    var featureBullets: [String] {
        switch self {
        case .basic:
            [
                String(localized: "1 active project"),
                String(localized: "Up to 3 team members"),
                String(localized: "5 GB photo & video storage"),
                String(localized: "Photos, video & GPS stamps"),
                String(localized: "Annotations & Before/After"),
                String(localized: "PDF reports"),
            ]
        case .pro:
            [
                String(localized: "Everything in Basic"),
                String(localized: "5 active projects"),
                String(localized: "Up to 10 team members"),
                String(localized: "50 GB storage"),
                String(localized: "Tasks, checklists & Pages"),
                String(localized: "Comments & @mentions"),
            ]
        case .premium:
            [
                String(localized: "Everything in Pro"),
                String(localized: "Unlimited projects"),
                String(localized: "Up to 25 team members"),
                String(localized: "150 GB storage"),
                String(localized: "AR / LiDAR measurement"),
                String(localized: "Dual camera (PiP) video"),
            ]
        }
    }

    var chipColorHex: String {
        switch self {
        case .basic: "#8D6E63"
        case .pro: "#1B98E0"
        case .premium: "#6C63FF"
        }
    }
}

/// Billing lifecycle of an organization, derived from its trial/subscription
/// dates. Local-first mock: subscribing is instant and free; real payments
/// arrive with cloud accounts.
enum SubscriptionStatus {
    /// Within the 7-day trial — full (Premium) access regardless of `planTier`.
    case trialing
    /// A paid plan is active.
    case active
    /// Trial ended with no subscription — the owner must choose a plan.
    case expired
}

/// Optional extra storage stacked on top of a plan's base storage. Local-first
/// mock: adding is instant and free; real billing arrives with cloud accounts.
enum StorageAddOn: String, Codable, CaseIterable {
    case none
    case plus50
    case plus250
    case plus1tb

    /// Extra bytes added to the plan's base `maxStorageBytes` (decimal).
    var bytes: Int64 {
        switch self {
        case .none: 0
        case .plus50: 50_000_000_000
        case .plus250: 250_000_000_000
        case .plus1tb: 1_000_000_000_000
        }
    }

    var displayName: String {
        switch self {
        case .none: String(localized: "No add-on")
        case .plus50: String(localized: "+50 GB")
        case .plus250: String(localized: "+250 GB")
        case .plus1tb: String(localized: "+1 TB")
        }
    }

    /// Monthly price (mock). Empty for `.none`.
    var price: String {
        switch self {
        case .none: ""
        case .plus50: "$5"
        case .plus250: "$18"
        case .plus1tb: "$50"
        }
    }

    /// The purchasable add-ons (excludes `.none`).
    static var purchasable: [StorageAddOn] { [.plus50, .plus250, .plus1tb] }
}
