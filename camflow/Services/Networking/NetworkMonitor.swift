import Foundation
import Network
import Observation

/// Observable reachability. Main-actor isolated (the project default) so views
/// and the sync engine can read `isOnline` directly; `NWPathMonitor` callbacks
/// hop back to the main actor to publish changes.
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true

    /// Fired on a connectivity transition (`true` = came online). The sync layer
    /// uses this to flush the outbox the moment the device reconnects.
    @ObservationIgnored var onChange: (@MainActor (Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.camflow.network-monitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let changed = self.isOnline != online
                self.isOnline = online
                if changed { self.onChange?(online) }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
