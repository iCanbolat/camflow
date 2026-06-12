import Foundation

/// Capabilities gated by a member's role in the active organization.
/// The single source of truth is `OrgMember.Role.can(_:)` below; call sites
/// ask `session.can(.manageTeam)` instead of comparing roles directly.
enum Permission {
    /// View the Plan & Billing screen and switch plan tiers.
    case manageBilling
    /// Edit the company profile: name, logo, contact info.
    case editCompanyProfile
    /// Soft-delete the organization. Owner only.
    case deleteOrganization
    /// Invite, edit, remove members and assign them to projects.
    case manageTeam
    /// Change another member's role.
    case changeRoles
    /// Create/edit/delete tags, project labels, and checklist templates.
    /// (Applying existing tags to photos is open to everyone.)
    case manageTaxonomy
    /// Create projects. Open to all roles; the plan tier limit gates it.
    case createProject
    /// Delete projects.
    case deleteProject
}

extension OrgMember.Role {
    func can(_ permission: Permission) -> Bool {
        switch self {
        case .owner:
            true
        case .admin:
            permission != .deleteOrganization
        case .manager:
            switch permission {
            case .manageTeam, .manageTaxonomy, .createProject, .deleteProject:
                true
            case .manageBilling, .editCompanyProfile, .deleteOrganization, .changeRoles:
                false
            }
        case .standard:
            permission == .createProject
        }
    }
}
