import Foundation
import SwiftData
import UIKit

/// A generated invite ready to share: the code plus both URL forms.
struct InviteLink {
    let code: String
    /// `https://camflow.app/invite/<code>` — opens the app when installed
    /// (universal link), the web landing page otherwise.
    let universalURL: URL
    /// `camflow://invite/<code>` — custom-scheme fallback used by the web
    /// landing page's "Open in CamFlow" button and for local testing.
    let customSchemeURL: URL
}

/// What the invitee sees before accepting: who invited them, into what.
struct InvitePreview {
    let organizationName: String
    let organizationLogoFileName: String?
    let memberName: String
    let roleDisplayName: String
}

enum InviteError: LocalizedError {
    case codeNotFound
    case organizationUnavailable
    case alreadyRedeemed
    /// The signed-in account already has a membership in the invite's
    /// organization; UI treats this as "switch to that org". Carries plain
    /// values (not the @Model) so the error stays Sendable.
    case alreadyMember(organizationID: UUID, organizationName: String)

    var errorDescription: String? {
        switch self {
        case .codeNotFound:
            String(localized: "This invite code isn't valid. Ask your team for a new link.")
        case .organizationUnavailable:
            String(localized: "The organization for this invite is no longer available.")
        case .alreadyRedeemed:
            String(localized: "This invite has already been used by someone else.")
        case .alreadyMember:
            String(localized: "You're already a member of this organization.")
        }
    }
}

/// Invite boundary. The cloud implementation is `ApiInviteService`: code
/// issuance, preview, validation and redemption all live on the backend, so an
/// invite link works across devices. The UI is unchanged behind this protocol.
@MainActor
protocol InviteService {
    /// Idempotent: returns the member's existing code or issues a new one.
    func issueInvite(for member: OrgMember) async throws -> InviteLink
    func preview(code: String) async throws -> InvitePreview
    /// Links `account` to the invited member row and returns the joined org.
    func redeem(code: String, account: Account) async throws -> Organization
}

/// Pure link/code helpers shared by the invite client and the URL handlers in
/// the app entry point.
enum InviteLinks {
    /// The one place the invite domain lives; swap when the real domain lands.
    static let webHost = "camflow.app"
    static let customScheme = "camflow"
    static let codeLength = 8
    /// Unambiguous alphabet: no 0/O, 1/I/L.
    static let alphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"

    static func generateCode() -> String {
        String((0..<codeLength).compactMap { _ in alphabet.randomElement() })
    }

    static func link(for code: String) -> InviteLink {
        InviteLink(
            code: code,
            universalURL: universalURL(for: code),
            customSchemeURL: customSchemeURL(for: code)
        )
    }

    static func universalURL(for code: String) -> URL {
        URL(string: "https://\(webHost)/invite/\(code)")!
    }

    static func customSchemeURL(for code: String) -> URL {
        URL(string: "\(customScheme)://invite/\(code)")!
    }

    /// Extracts the invite code from either URL form, or nil if the URL is
    /// not an invite link.
    static func code(from url: URL) -> String? {
        switch url.scheme?.lowercased() {
        case "https", "http":
            guard let host = url.host()?.lowercased(),
                  host == webHost || host == "www.\(webHost)" else { return nil }
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count == 2, parts[0] == "invite" else { return nil }
            return normalizedCode(parts[1])
        case customScheme:
            // camflow://invite/CODE parses with host "invite".
            guard url.host()?.lowercased() == "invite" else { return nil }
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count == 1 else { return nil }
            return normalizedCode(parts[0])
        default:
            return nil
        }
    }

    /// Trims, uppercases and validates manual input against the code format.
    static func normalizedCode(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == codeLength, code.allSatisfy({ alphabet.contains($0) }) else {
            return nil
        }
        return code
    }
}

/// Detects an invite link on the pasteboard without triggering the paste
/// banner unless a probable URL is actually present (pattern detection is
/// silent; only reading values shows the banner).
@MainActor
enum InviteClipboard {
    private static var hasCheckedThisLaunch = false

    static func detectInviteCode() async -> String? {
        guard !hasCheckedThisLaunch else { return nil }
        hasCheckedThisLaunch = true
        let pasteboard = UIPasteboard.general
        guard let patterns = try? await pasteboard.detectedPatterns(for: [\.probableWebURL]),
              patterns.contains(\.probableWebURL) else { return nil }
        guard let values = try? await pasteboard.detectedValues(for: [\.probableWebURL]),
              let url = URL(string: values.probableWebURL) else { return nil }
        return InviteLinks.code(from: url)
    }
}
