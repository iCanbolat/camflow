import Foundation

/// Errors surfaced by `APIClient`: transport failures plus the backend's
/// consistent JSON error envelope. `nonisolated` + `Sendable` so it crosses the
/// networking actors freely.
nonisolated enum APIError: LocalizedError, Sendable {
    /// No connectivity — the caller should queue and retry on reconnect.
    case offline
    case transport(message: String)
    case decoding(message: String)
    /// Non-2xx with a decodable backend envelope (carries a machine `code`).
    case server(ServerError)
    /// 401 that survived a refresh attempt — the session is no longer valid.
    case unauthorized
    /// Non-2xx without a decodable envelope.
    case unexpected(status: Int, body: String?)

    /// Machine-readable code (`codeNotFound`, `alreadyMember`, …) when present.
    var code: String? {
        if case let .server(error) = self { return error.code }
        return nil
    }

    var statusCode: Int? {
        switch self {
        case let .server(error): return error.statusCode
        case let .unexpected(status, _): return status
        case .unauthorized: return 401
        case .offline, .transport, .decoding: return nil
        }
    }

    /// A human-readable message suitable for surfacing in the UI.
    var userMessage: String {
        switch self {
        case .offline:
            return String(localized: "You're offline. Changes will sync when you reconnect.")
        case let .transport(message), let .decoding(message):
            return message
        case let .server(error):
            return error.message
        case .unauthorized:
            return String(localized: "Your session expired. Please sign in again.")
        case let .unexpected(status, _):
            return String(localized: "Something went wrong (\(status)).")
        }
    }

    var errorDescription: String? { userMessage }
}

/// The backend's error JSON: `{ statusCode, error, message, code?, ... }`.
/// `message` may be a string or an array of strings (validation errors), and
/// some errors (e.g. `alreadyMember`) carry extra fields.
nonisolated struct ServerError: Error, Sendable, Decodable {
    let statusCode: Int
    let error: String?
    let message: String
    let code: String?
    let organizationId: String?
    let organizationName: String?

    private enum CodingKeys: String, CodingKey {
        case statusCode, error, message, code, organizationId, organizationName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statusCode = (try? container.decode(Int.self, forKey: .statusCode)) ?? 0
        error = try? container.decode(String.self, forKey: .error)
        code = try? container.decode(String.self, forKey: .code)
        organizationId = try? container.decode(String.self, forKey: .organizationId)
        organizationName = try? container.decode(String.self, forKey: .organizationName)
        if let single = try? container.decode(String.self, forKey: .message) {
            message = single
        } else if let many = try? container.decode([String].self, forKey: .message) {
            message = many.joined(separator: "\n")
        } else {
            message = String(localized: "Request failed.")
        }
    }
}
