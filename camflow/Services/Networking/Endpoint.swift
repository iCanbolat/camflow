import Foundation

nonisolated enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// A typed description of one API call, relative to `APIConfig.apiPrefix`.
/// `nonisolated` + `Sendable` so it can be built anywhere and handed to the
/// `APIClient` actor.
nonisolated struct Endpoint: Sendable {
    var method: HTTPMethod
    var path: String
    var query: [URLQueryItem] = []
    var body: Data?
    var requiresAuth: Bool = true

    static func get(
        _ path: String,
        query: [URLQueryItem] = [],
        requiresAuth: Bool = true
    ) -> Endpoint {
        Endpoint(method: .get, path: path, query: query, requiresAuth: requiresAuth)
    }

    static func delete(_ path: String, requiresAuth: Bool = true) -> Endpoint {
        Endpoint(method: .delete, path: path, requiresAuth: requiresAuth)
    }

    static func post(
        _ path: String,
        body: Data? = nil,
        requiresAuth: Bool = true
    ) -> Endpoint {
        Endpoint(method: .post, path: path, body: body, requiresAuth: requiresAuth)
    }

    /// JSON-body convenience for POST.
    static func post(
        _ path: String,
        json: some Encodable & Sendable,
        requiresAuth: Bool = true
    ) throws -> Endpoint {
        Endpoint(
            method: .post,
            path: path,
            body: try JSONCoding.makeEncoder().encode(json),
            requiresAuth: requiresAuth
        )
    }

    /// JSON-body convenience for PATCH.
    static func patch(
        _ path: String,
        json: some Encodable & Sendable,
        requiresAuth: Bool = true
    ) throws -> Endpoint {
        Endpoint(
            method: .patch,
            path: path,
            body: try JSONCoding.makeEncoder().encode(json),
            requiresAuth: requiresAuth
        )
    }
}
