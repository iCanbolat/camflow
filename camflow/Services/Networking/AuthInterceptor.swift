import Foundation

/// Coordinates access-token refresh. **Single-flight**: concurrent 401s share a
/// single `/auth/refresh` call. On failure it clears the session and fires
/// `onSignOutRequired` so the app can route back to the auth screen. The backend
/// rotates the refresh token and detects reuse.
actor AuthInterceptor {
    private let tokens: TokenStore
    private let session: URLSession
    private var inFlight: Task<String, Error>?
    private var onSignOutRequired: (@Sendable () -> Void)?

    init(tokens: TokenStore, session: URLSession = .shared) {
        self.tokens = tokens
        self.session = session
    }

    func setSignOutHandler(_ handler: @escaping @Sendable () -> Void) {
        onSignOutRequired = handler
    }

    /// Returns a fresh access token, performing at most one refresh across all
    /// concurrent callers.
    func refresh() async throws -> String {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task<String, Error> { try await self.performRefresh() }
        inFlight = task
        do {
            let access = try await task.value
            inFlight = nil
            return access
        } catch {
            inFlight = nil
            await tokens.clear()
            onSignOutRequired?()
            throw error
        }
    }

    private func performRefresh() async throws -> String {
        guard let refreshToken = await tokens.refreshToken else {
            throw APIError.unauthorized
        }

        let url = APIConfig.baseURL.appending(path: APIConfig.apiPrefix + "/auth/refresh")
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONCoding.makeEncoder()
            .encode(RefreshRequest(refreshToken: refreshToken))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw APIError.unauthorized
        }

        let decoded = try JSONCoding.makeDecoder().decode(RefreshResponse.self, from: data)
        await tokens.setTokens(access: decoded.accessToken, refresh: decoded.refreshToken)
        return decoded.accessToken
    }
}

private nonisolated struct RefreshRequest: Encodable, Sendable {
    let refreshToken: String
}

private nonisolated struct RefreshResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
}
