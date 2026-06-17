import Foundation

/// `POST /devices` body — registers this install's APNs token for the account.
nonisolated struct RegisterDeviceBody: Encodable, Sendable {
    let token: String
    let platform: String
}
