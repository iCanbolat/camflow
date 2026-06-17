import Foundation

enum AuthError: LocalizedError {
    case invalidEmail
    case weakPassword
    case emailInUse
    case accountNotFound
    case wrongPassword
    /// A provider sign-in path the app can't complete yet (e.g. Google before
    /// its SDK lands). Carries a user-facing message.
    case unsupportedProvider(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail: String(localized: "Enter a valid email address.")
        case .weakPassword: String(localized: "Password must be at least 6 characters.")
        case .emailInUse: String(localized: "An account with this email already exists.")
        case .accountNotFound: String(localized: "No account found for that email.")
        case .wrongPassword: String(localized: "Incorrect password.")
        case let .unsupportedProvider(message): message
        }
    }
}

/// Auth boundary. The cloud implementation is `ApiAuthService`, which exchanges
/// credentials with the backend, stores the token pair (access in RAM, refresh
/// in the Keychain), and mirrors the returned `Account` into SwiftData. Social
/// sign-in takes the provider credential captured by the UI; the server
/// verifies it against Apple/Google.
@MainActor
protocol AuthService {
    func signUp(email: String, password: String, displayName: String) async throws -> Account
    func signIn(email: String, password: String) async throws -> Account
    func signInWithApple(identityToken: String, displayName: String?) async throws -> Account
    func signInWithGoogle(idToken: String) async throws -> Account
}
