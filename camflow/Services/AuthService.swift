import Foundation
import SwiftData
import CryptoKit

enum AuthError: LocalizedError {
    case invalidEmail
    case weakPassword
    case emailInUse
    case accountNotFound
    case wrongPassword

    var errorDescription: String? {
        switch self {
        case .invalidEmail: String(localized: "Enter a valid email address.")
        case .weakPassword: String(localized: "Password must be at least 6 characters.")
        case .emailInUse: String(localized: "An account with this email already exists.")
        case .accountNotFound: String(localized: "No account found for that email.")
        case .wrongPassword: String(localized: "Incorrect password.")
        }
    }
}

/// Auth boundary. The local scaffold ships `MockAuthService`; the cloud phase
/// will add a `SupabaseAuthService`/`FirebaseAuthService` conforming to the same
/// protocol so the UI doesn't change.
@MainActor
protocol AuthService {
    func signUp(email: String, password: String, displayName: String) async throws -> Account
    func signIn(email: String, password: String) async throws -> Account
    func signInWithApple() async throws -> Account
    func signInWithGoogle() async throws -> Account
}

/// Local, offline implementation. Email/password is verified against a SHA-256
/// hash stored on `Account`; Apple/Google "sign in" creates or finds a
/// provider-tagged demo account. No network — credentials are mock-only.
@MainActor
struct MockAuthService: AuthService {
    let context: ModelContext

    func signUp(email rawEmail: String, password: String, displayName: String) async throws -> Account {
        let email = Self.normalize(rawEmail)
        try Self.validate(email: email, password: password)
        if Self.account(email: email, context: context) != nil {
            throw AuthError.emailInUse
        }
        let name = displayName.trimmingCharacters(in: .whitespaces)
        let account = Account(
            email: email,
            displayName: name.isEmpty ? Self.nameFromEmail(email) : name,
            provider: .email,
            passwordHash: Self.hash(password),
            colorHex: Self.color(for: email)
        )
        context.insert(account)
        return account
    }

    func signIn(email rawEmail: String, password: String) async throws -> Account {
        let email = Self.normalize(rawEmail)
        guard let account = Self.account(email: email, context: context) else {
            throw AuthError.accountNotFound
        }
        guard account.passwordHash == Self.hash(password) else {
            throw AuthError.wrongPassword
        }
        return account
    }

    func signInWithApple() async throws -> Account {
        // TODO: Supabase/Firebase — exchange the ASAuthorizationAppleIDCredential
        // for a real session here. Scaffold creates/finds a local Apple account.
        try findOrCreateProviderAccount(
            provider: .apple,
            email: "apple.user@camflow.app",
            displayName: "Apple User"
        )
    }

    func signInWithGoogle() async throws -> Account {
        // TODO: Supabase/Firebase — complete the Google OAuth flow here. Scaffold
        // creates/finds a local Google account.
        try findOrCreateProviderAccount(
            provider: .google,
            email: "google.user@camflow.app",
            displayName: "Google User"
        )
    }

    private func findOrCreateProviderAccount(
        provider: Account.Provider,
        email: String,
        displayName: String
    ) throws -> Account {
        if let existing = Self.account(email: email, context: context) {
            return existing
        }
        let account = Account(
            email: email,
            displayName: displayName,
            provider: provider,
            colorHex: Self.color(for: email)
        )
        context.insert(account)
        return account
    }

    // MARK: - Helpers

    private static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func validate(email: String, password: String) throws {
        guard email.contains("@"), email.contains(".") else { throw AuthError.invalidEmail }
        guard password.count >= 6 else { throw AuthError.weakPassword }
    }

    private static func hash(_ password: String) -> String {
        let digest = SHA256.hash(data: Data(password.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func nameFromEmail(_ email: String) -> String {
        String(email.prefix(while: { $0 != "@" })).capitalized
    }

    private static func color(for email: String) -> String {
        TagPalette.colors[abs(email.hashValue) % TagPalette.colors.count]
    }

    private static func account(email: String, context: ModelContext) -> Account? {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.email == email && $0.deletedAt == nil }
        )
        return (try? context.fetch(descriptor))?.first
    }
}
