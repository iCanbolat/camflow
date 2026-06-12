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
        case .basic: String(localized: "Get started for free")
        case .pro: String(localized: "For growing crews")
        case .premium: String(localized: "Every tool on the truck")
        }
    }

    /// nil = unlimited.
    var maxActiveProjects: Int? {
        switch self {
        case .basic: 3
        case .pro, .premium: nil
        }
    }

    /// Includes the owner. nil = unlimited.
    var maxMembers: Int? {
        switch self {
        case .basic: 3
        case .pro, .premium: nil
        }
    }

    var includesARMeasure: Bool { self == .premium }
    var includesDualCapture: Bool { self == .premium }

    var featureBullets: [String] {
        switch self {
        case .basic:
            [
                String(localized: "Up to 3 active projects"),
                String(localized: "Up to 3 team members"),
                String(localized: "Photos, video, annotations & tags"),
                String(localized: "Tasks, checklists & PDF reports"),
            ]
        case .pro:
            [
                String(localized: "Unlimited projects"),
                String(localized: "Unlimited team members"),
                String(localized: "Everything in Basic"),
            ]
        case .premium:
            [
                String(localized: "Everything in Pro"),
                String(localized: "AR point-to-point measurement"),
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
