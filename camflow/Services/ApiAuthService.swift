import Foundation
import SwiftData

/// Cloud `AuthService`: trades credentials with `/auth/*`, persists the token
/// pair via `TokenStore`, and upserts the returned account into SwiftData so the
/// rest of the app keeps reading its local source of truth. Backend error codes
/// are mapped onto the existing `AuthError` cases so the UI is unchanged.
@MainActor
struct ApiAuthService: AuthService {
    let api: APIClient
    let tokens: TokenStore
    let context: ModelContext

    func signUp(email: String, password: String, displayName: String) async throws -> Account {
        let body = SignUpBody(
            email: email.trimmingCharacters(in: .whitespaces).lowercased(),
            password: password,
            displayName: displayName.trimmingCharacters(in: .whitespaces)
        )
        return try await authenticate(.post("/auth/sign-up", json: body, requiresAuth: false))
    }

    func signIn(email: String, password: String) async throws -> Account {
        let body = SignInBody(
            email: email.trimmingCharacters(in: .whitespaces).lowercased(),
            password: password
        )
        return try await authenticate(.post("/auth/sign-in", json: body, requiresAuth: false))
    }

    func signInWithApple(identityToken: String, displayName: String?) async throws -> Account {
        let body = AppleSignInBody(identityToken: identityToken, displayName: displayName)
        return try await authenticate(.post("/auth/apple", json: body, requiresAuth: false))
    }

    func signInWithGoogle(idToken: String) async throws -> Account {
        let body = GoogleSignInBody(idToken: idToken)
        return try await authenticate(.post("/auth/google", json: body, requiresAuth: false))
    }

    // MARK: - Internals

    /// Runs an auth call, stores the issued tokens, and mirrors the account.
    private func authenticate(_ endpoint: @autoclosure () throws -> Endpoint) async throws -> Account {
        let endpoint = try endpoint()
        do {
            let session: SessionResponseDTO = try await api.send(endpoint)
            await tokens.setTokens(access: session.accessToken, refresh: session.refreshToken)
            let account = CloudMappers.upsertAccount(session.account, in: context)
            try? context.save()
            return account
        } catch let error as APIError {
            throw Self.mapped(error)
        }
    }

    /// Maps backend error codes onto the localized `AuthError` cases the UI
    /// already understands; everything else surfaces the API error as-is.
    private static func mapped(_ error: APIError) -> Error {
        switch error.code {
        case "emailInUse": AuthError.emailInUse
        case "accountNotFound": AuthError.accountNotFound
        case "wrongPassword": AuthError.wrongPassword
        default: error
        }
    }
}
