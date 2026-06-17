import Foundation
import SwiftData
import Observation

/// Orchestrates one offline-first sync cycle per organization: **push then pull**,
/// gated by reachability and a valid session. Networking runs on the main actor
/// (the `APIClient` is itself an `actor`); SwiftData work is delegated to the
/// background `SyncActor`. `@Observable` so a status banner/indicator can read
/// `state`/`lastSyncedAt` (Phase 5).
@MainActor
@Observable
final class SyncEngine {
    enum State: Equatable {
        case idle
        case syncing
        case offline
        case error(String)
    }

    private(set) var state: State = .idle
    private(set) var lastSyncedAt: Date?

    /// Fired after a successful cycle. `AppServices` uses it to flush media
    /// uploads once their photo rows are guaranteed to exist server-side.
    var onCycleComplete: (@MainActor () -> Void)?

    private let api: APIClient
    private let syncActor: SyncActor
    private let monitor: NetworkMonitor
    private let tokens: TokenStore
    private let cursors = SyncCursorStore()
    private let deviceID: String

    /// Serializes cycles: a second trigger while one runs is dropped (the next
    /// periodic/foreground tick will catch any work it missed).
    private var isRunning = false
    private var periodicTask: Task<Void, Never>?

    /// Page size for both pull and push batches (backend caps push at 500).
    private let pageLimit = 200

    init(api: APIClient, syncActor: SyncActor, monitor: NetworkMonitor, tokens: TokenStore) {
        self.api = api
        self.syncActor = syncActor
        self.monitor = monitor
        self.tokens = tokens
        self.deviceID = Self.resolveDeviceID()
    }

    // MARK: - Triggers

    /// Runs a full push→pull cycle for the org. No-op without an org, while
    /// offline, without a session, or when a cycle is already in flight.
    func sync(organizationID: UUID?) async {
        guard let orgID = organizationID else { return }
        guard !isRunning else { return }
        guard monitor.isOnline else { state = .offline; return }
        guard await tokens.hasSession else { return }

        isRunning = true
        defer { isRunning = false }
        state = .syncing
        do {
            try await push(orgID)
            try await pull(orgID)
            lastSyncedAt = .now
            state = .idle
            onCycleComplete?()
        } catch let error as APIError {
            if case .offline = error { state = .offline } else { state = .error(error.userMessage) }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Fire-and-forget trigger (foreground, org switch, "Sync now").
    func requestSync(organizationID: UUID?) {
        Task { await sync(organizationID: organizationID) }
    }

    /// Starts a periodic cycle; re-reads the active org each tick so an org
    /// switch is picked up without extra wiring. Replaces any prior loop. The
    /// `organization` closure runs on the main actor (it reads `Session`).
    func startPeriodic(every seconds: TimeInterval, organization: @escaping @MainActor () -> UUID?) {
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                await self?.sync(organizationID: organization())
            }
        }
    }

    func stop() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    /// Clears every per-org cursor (sign-out): the next account bootstraps fresh.
    func resetCursors() {
        cursors.clearAll()
    }

    // MARK: - Push

    private func push(_ orgID: UUID) async throws {
        let mutations = await syncActor.collectOutbox(organizationID: orgID)
        guard !mutations.isEmpty else { return }
        for chunk in mutations.chunked(into: pageLimit) {
            let request = SyncPushRequest(deviceId: deviceID, mutations: chunk)
            let response: SyncPushResponse = try await api.send(.post("/sync/push", json: request))
            await syncActor.applyAcks(response.results, pushed: chunk)
        }
    }

    // MARK: - Pull

    private func pull(_ orgID: UUID) async throws {
        var cursor = cursors.cursor(for: orgID)
        while true {
            let query = [
                URLQueryItem(name: "organizationId", value: orgID.uuidString),
                URLQueryItem(name: "since", value: String(cursor)),
                URLQueryItem(name: "limit", value: String(pageLimit)),
            ]
            let response: SyncPullResponse = try await api.send(.get("/sync/pull", query: query))
            await syncActor.apply(changes: response.changes)
            cursor = response.nextCursor
            cursors.setCursor(cursor, for: orgID)
            if !response.hasMore { break }
        }
    }

    // MARK: - Device id

    /// Stable per-install id sent on push (lets the backend attribute/echo-filter
    /// changes; SSE in Phase 4 uses it to skip self-originated events).
    private static func resolveDeviceID() -> String {
        let key = "syncDeviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}

private nonisolated extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
