import UIKit
import UserNotifications
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

/// Minimal `UIApplicationDelegate` adaptor for the SwiftUI app: APNs token
/// registration, notification presentation/taps, and the background-`URLSession`
/// relaunch handler. It owns no state — everything is forwarded to `PushBridge`,
/// which `AppServices` wires up.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Completes the Google Sign-In redirect (no-op until the SDK is linked).
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        #if canImport(GoogleSignIn)
        return GIDSignIn.sharedInstance.handle(url)
        #else
        return false
        #endif
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushBridge.shared.deliver(token: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Expected on the simulator / without a push-enabled provisioning profile.
    }

    /// The OS relaunched us (or resumed) to finish background transfers; hand the
    /// completion handler to whoever owns the background session (`MediaUploader`).
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        PushBridge.shared.backgroundCompletionHandler = completionHandler
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show the banner + badge even when the app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .badge, .sound]
    }

    /// Tap → route the payload's deep link through the shared URL handler.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        if let link = info["deepLink"] as? String, let url = URL(string: link) {
            PushBridge.shared.deliver(deepLink: url)
        }
    }
}
