import Foundation

/// Resolves the backend base URL and API prefix. `nonisolated` so the
/// networking actors can read it off the main actor.
///
/// Override at launch with `-apiBaseURL http://192.168.x.x:3000` (registered
/// into `UserDefaults` via the argument domain) to point a device/simulator at
/// a local backend.
nonisolated enum APIConfig {
    /// Versioned REST prefix. SSE lives under the same host but a different path.
    static let apiPrefix = "/api/v1"

    static let baseURL: URL = {
        if let override = UserDefaults.standard.string(forKey: "apiBaseURL"),
           let url = URL(string: override) {
            return url
        }
        #if DEBUG
        return URL(string: "http://localhost:3000")!
        #else
        return URL(string: "https://api.camflow.app")!
        #endif
    }()
}
