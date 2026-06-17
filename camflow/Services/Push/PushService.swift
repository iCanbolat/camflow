import Foundation
import UIKit
import UserNotifications

/// Owns APNs registration and the notification-related backend calls (device
/// register/unregister, mark-read, badge). Everything no-ops cleanly without a
/// cloud session or push permission, so DEBUG/local flows are unaffected.
@MainActor
final class PushService {
    private let api: APIClient
    private let tokens: TokenStore
    private var lastToken: String?

    init(api: APIClient, tokens: TokenStore) {
        self.api = api
        self.tokens = tokens
    }

    /// Priming flow: prompt for permission, then register for APNs if granted.
    func requestAuthorization() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Re-register on launch when already authorized (the token can rotate).
    func registerIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// APNs token → `POST /devices`. No-op without a session.
    func registerDevice(tokenData: Data) async {
        guard await tokens.hasSession else { return }
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        lastToken = token
        guard let endpoint = try? Endpoint.post("/devices", json: RegisterDeviceBody(token: token, platform: "ios")) else { return }
        let _: Void? = try? await api.send(endpoint)
    }

    /// `DELETE /devices/:token` on sign-out so the account stops receiving pushes
    /// on this install. Must run while the session is still valid.
    func unregisterDevice() async {
        guard let token = lastToken else { return }
        let _: Void? = try? await api.send(.delete("/devices/\(token)"))
        lastToken = nil
    }

    func markRead(notificationID: UUID) async {
        let _: Void? = try? await api.send(.post("/notifications/\(notificationID.uuidString)/read"))
    }

    func markAllRead(organizationID: UUID) async {
        var endpoint = Endpoint.post("/notifications/read-all")
        endpoint.query = [URLQueryItem(name: "organizationId", value: organizationID.uuidString)]
        let _: Void? = try? await api.send(endpoint)
    }

    func setBadge(_ count: Int) {
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
    }
}
