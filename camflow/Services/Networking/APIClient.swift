import Foundation

/// Off-main HTTP client. Attaches bearer auth, decodes JSON, and retries once
/// after a single-flight token refresh on 401. An `actor` so it shares one
/// `URLSession` and decoder safely across concurrent callers.
actor APIClient {
    private let session: URLSession
    private let tokens: TokenStore
    private let interceptor: AuthInterceptor
    private let decoder = JSONCoding.makeDecoder()

    init(tokens: TokenStore, interceptor: AuthInterceptor, session: URLSession = .shared) {
        self.tokens = tokens
        self.interceptor = interceptor
        self.session = session
    }

    /// Sends a request and decodes a JSON response.
    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> Response {
        let data = try await data(for: endpoint)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(message: "Failed to decode \(Response.self).")
        }
    }

    /// Sends a request and ignores the response body (204 / fire-and-forget).
    func send(_ endpoint: Endpoint) async throws {
        _ = try await data(for: endpoint)
    }

    // MARK: - Internals

    private func data(for endpoint: Endpoint) async throws -> Data {
        let request = try await makeRequest(endpoint, accessOverride: nil)
        let (data, http) = try await perform(request)

        if http.statusCode == 401, endpoint.requiresAuth {
            // Refresh once (single-flight) and retry.
            let newAccess = try await interceptor.refresh()
            let retry = try await makeRequest(endpoint, accessOverride: newAccess)
            let (retryData, retryHTTP) = try await perform(retry)
            return try validate(retryData, retryHTTP)
        }
        return try validate(data, http)
    }

    private func makeRequest(_ endpoint: Endpoint, accessOverride: String?) async throws -> URLRequest {
        let url = APIConfig.baseURL.appending(path: APIConfig.apiPrefix + endpoint.path)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if !endpoint.query.isEmpty { components?.queryItems = endpoint.query }
        guard let resolved = components?.url else {
            throw APIError.transport(message: "Invalid URL for \(endpoint.path).")
        }

        var request = URLRequest(url: resolved)
        request.httpMethod = endpoint.method.rawValue
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if endpoint.requiresAuth {
            let token: String?
            if let accessOverride {
                token = accessOverride
            } else {
                token = await tokens.accessToken
            }
            if let token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw APIError.offline
        } catch {
            throw APIError.transport(message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(message: "Non-HTTP response.")
        }
        return (data, http)
    }

    private func validate(_ data: Data, _ http: HTTPURLResponse) throws -> Data {
        if (200..<300).contains(http.statusCode) { return data }
        if http.statusCode == 401 { throw APIError.unauthorized }
        if let server = try? decoder.decode(ServerError.self, from: data) {
            throw APIError.server(server)
        }
        throw APIError.unexpected(status: http.statusCode, body: String(data: data, encoding: .utf8))
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .networkConnectionLost,
        .dataNotAllowed,
        .cannotConnectToHost,
        .timedOut,
    ]
}

/// Shared JSON coding configured to match the backend's ISO-8601 timestamps
/// (with optional fractional seconds). `ISO8601FormatStyle` is a `Sendable`
/// value type, so the custom strategies are concurrency-safe.
nonisolated enum JSONCoding {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(fractional))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = parseDate(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date: \(string)"
                )
            }
            return date
        }
        return decoder
    }

    /// Parses a backend ISO-8601 timestamp (with or without fractional seconds).
    /// Used by the sync layer, where dates arrive as strings inside dynamic rows.
    static func parseDate(_ string: String) -> Date? {
        if let date = try? fractional.parse(string) { return date }
        if let date = try? plain.parse(string) { return date }
        return nil
    }

    /// Formats a `Date` as the backend's fractional ISO-8601 string (matching the
    /// encoder), for sync push payload fields carried as `JSONValue.string`.
    static func iso(_ date: Date) -> String {
        date.formatted(fractional)
    }
}
