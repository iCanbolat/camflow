import Foundation
import Observation

/// Consumes the backend's per-org Server-Sent Events stream (`/realtime/:orgId`,
/// bearer-authed) and, on each `change` signal, triggers a debounced `/sync/pull`
/// (pull stays the source of truth). Reconnects with capped backoff, refreshes a
/// 401 once, and is gated by reachability + a live session. `@MainActor` so the
/// lifecycle (foreground / org switch) is driven from the UI layer.
@MainActor
@Observable
final class RealtimeClient {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
    }

    private(set) var state: State = .disconnected

    /// Fired (debounced) on a `change` event — `AppServices` wires this to a sync.
    var onChange: (@MainActor () -> Void)?

    private let tokens: TokenStore
    private let interceptor: AuthInterceptor
    private let monitor: NetworkMonitor

    private var organizationID: UUID?
    private var loopTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    private let maxBackoff: UInt64 = 30
    private let debounceMs: UInt64 = 400

    init(tokens: TokenStore, interceptor: AuthInterceptor, monitor: NetworkMonitor) {
        self.tokens = tokens
        self.interceptor = interceptor
        self.monitor = monitor
    }

    /// Streams the given org. Idempotent: a no-op if already streaming it. Passing
    /// nil (or a different org) tears the current stream down first.
    func connect(organizationID newOrg: UUID?) {
        guard let newOrg else { stop(); return }
        if organizationID == newOrg, loopTask != nil { return }
        stop()
        organizationID = newOrg
        loopTask = Task { [weak self] in await self?.runLoop(orgID: newOrg) }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        organizationID = nil
        state = .disconnected
    }

    // MARK: - Loop

    private func runLoop(orgID: UUID) async {
        var backoff: UInt64 = 1
        while !Task.isCancelled {
            guard monitor.isOnline, await tokens.hasSession else {
                try? await Task.sleep(for: .seconds(3))
                continue
            }
            do {
                try await stream(orgID: orgID)
                backoff = 1 // a clean stream end → reconnect promptly
            } catch is CancellationError {
                return
            } catch {
                // Other failures fall through to backoff + reconnect.
            }
            state = .disconnected
            if Task.isCancelled { return }
            try? await Task.sleep(for: .seconds(Double(min(backoff, maxBackoff))))
            backoff = min(backoff * 2, maxBackoff)
        }
    }

    private func stream(orgID: UUID) async throws {
        guard let token = await tokens.accessToken else {
            _ = try? await interceptor.refresh()
            throw URLError(.userAuthenticationRequired)
        }

        let url = APIConfig.baseURL.appending(path: APIConfig.apiPrefix + "/realtime/\(orgID.uuidString)")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        state = .connecting
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 401 {
            _ = try? await interceptor.refresh()
            throw URLError(.userAuthenticationRequired)
        }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }

        state = .connected
        var eventType = ""
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            if line.isEmpty {
                if eventType == "change" { scheduleChange() }
                eventType = ""
            } else if line.hasPrefix("event:") {
                eventType = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
            }
            // `data:` payloads are ignored — a `change` signal just triggers a pull.
        }
    }

    private func scheduleChange() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(self?.debounceMs ?? 400)))
            guard let self, !Task.isCancelled else { return }
            self.onChange?()
        }
    }
}
