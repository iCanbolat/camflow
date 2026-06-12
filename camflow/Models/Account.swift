import Foundation
import SwiftData

/// The signed-in app user. In the local-first scaffold this lives in SwiftData
/// alongside everything else; the cloud phase will mirror it to a real auth
/// provider (Supabase/Firebase) keyed by the same `id`.
@Model
final class Account {
    enum Provider: String, Codable {
        case email
        case google
        case apple
    }

    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var email: String
    var displayName: String
    var provider: Provider
    /// SHA-256 of the password for the mock email provider only. **Not**
    /// production-secure — the real backend owns credentials in the cloud phase.
    var passwordHash: String?
    /// Avatar color.
    var colorHex: String

    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStatus: SyncStatus

    init(
        email: String,
        displayName: String,
        provider: Provider,
        passwordHash: String? = nil,
        colorHex: String = TagPalette.colors[0]
    ) {
        self.id = UUID()
        self.email = email
        self.displayName = displayName
        self.provider = provider
        self.passwordHash = passwordHash
        self.colorHex = colorHex
        self.createdAt = .now
        self.updatedAt = .now
        self.deletedAt = nil
        self.syncStatus = .local
    }
}

extension Account {
    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first)
        return letters.isEmpty ? String(email.prefix(1)).uppercased() : String(letters).uppercased()
    }
}
