import Foundation

/// Decouples the `AppDelegate` (created by SwiftUI, no access to `AppServices`)
/// from the cloud layer. The delegate delivers APNs tokens, notification-tap deep
/// links, and the background-`URLSession` completion handler here; `AppServices`
/// installs handlers in `start()`. Values that arrive before a handler is set are
/// buffered and replayed (cold-launch ordering).
@MainActor
final class PushBridge {
    static let shared = PushBridge()
    private init() {}

    /// Set by `MediaUploader` (its background session's `didFinishEvents`) and
    /// invoked so the OS knows background transfers are flushed.
    var backgroundCompletionHandler: (() -> Void)?

    private var tokenHandler: ((Data) -> Void)?
    private var deepLinkHandler: ((URL) -> Void)?
    private var pendingToken: Data?
    private var pendingDeepLink: URL?

    func setTokenHandler(_ handler: @escaping (Data) -> Void) {
        tokenHandler = handler
        if let pendingToken {
            handler(pendingToken)
            self.pendingToken = nil
        }
    }

    func setDeepLinkHandler(_ handler: @escaping (URL) -> Void) {
        deepLinkHandler = handler
        if let pendingDeepLink {
            handler(pendingDeepLink)
            self.pendingDeepLink = nil
        }
    }

    func deliver(token: Data) {
        if let tokenHandler { tokenHandler(token) } else { pendingToken = token }
    }

    func deliver(deepLink url: URL) {
        if let deepLinkHandler { deepLinkHandler(url) } else { pendingDeepLink = url }
    }
}
