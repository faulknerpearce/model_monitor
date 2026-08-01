import Foundation
import Combine
import os

@MainActor
final class OpenCodeUsagePoller: ObservableObject {
    @Published private(set) var snapshot: OpenCodeSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefreshedAt: Date?
    @Published private(set) var dataSourceLabel: String?
    @Published var menuIsOpen = false

    private let settings: AppSettings
    private let auth: OpenCodeAuthSession
    private let logger = Logger(subsystem: "com.grokmonitor.app", category: "OpenCode")

    private var timerTask: Task<Void, Never>?

    init(settings: AppSettings, auth: OpenCodeAuthSession) {
        self.settings = settings
        self.auth = auth
    }

    deinit {
        timerTask?.cancel()
    }

    func start() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            await self?.refreshNow()
            while !Task.isCancelled {
                guard let interval = self?.currentInterval() else { return }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                guard let self else { return }
                await self.refreshNow()
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    func clearSnapshot() {
        snapshot = nil
        lastError = nil
        dataSourceLabel = nil
    }

    func refreshNow() async {
        guard settings.selectedProvider == .opencode else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Prefer official console Go usage (matches opencode.ai bars).
        if let cookie = auth.cookieHeader(), !cookie.isEmpty {
            do {
                let client = OpenCodeConsoleClient(cookieHeader: cookie)
                let (consoleSnap, workspaceID) = try await client.fetchGoUsageSnapshot(
                    knownWorkspaceID: auth.workspaceID
                )
                auth.saveWorkspaceID(workspaceID)

                // Optional local model/token detail (does not affect limit %).
                let local = try? await Task.detached(priority: .userInitiated) {
                    try OpenCodeLocalStats.fetchSnapshot()
                }.value
                var snap = consoleSnap
                if let local {
                    snap = Self.mergeLocalModels(into: snap, local: local)
                }
                guard !Task.isCancelled else { return }
                snapshot = snap
                lastError = nil
                lastRefreshedAt = Date()
                dataSourceLabel = "OpenCode console"
                auth.needsSignIn = false
                let pct = snap.windows.first { $0.kind == .weekly }?.usedPercent ?? snap.primaryUsedPercent
                logger.info(
                    "OpenCode console refresh: weekly \(pct, format: .fixed(precision: 1))%"
                )
                return
            } catch let error as OpenCodeConsoleError {
                switch error {
                case .unauthorized, .notSignedIn:
                    auth.markSessionInvalid(reason: error.localizedDescription)
                default:
                    break
                }
                logger.error("OpenCode console fetch failed: \(error.localizedDescription, privacy: .public)")
                // Fall through to local estimate only if we already had no better data path.
            } catch {
                logger.error("OpenCode console fetch failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Local estimate fallback (labeled).
        do {
            let snap = try await Task.detached(priority: .userInitiated) {
                try OpenCodeLocalStats.fetchSnapshot()
            }.value
            guard !Task.isCancelled else { return }
            snapshot = snap
            dataSourceLabel = "Local estimate"
            if auth.cookieHeader() == nil || auth.cookieHeader()?.isEmpty == true {
                lastError = "Showing local estimate. Sign in to OpenCode for official Go usage."
            } else if auth.needsSignIn {
                lastError = "Console session expired — showing local estimate. Sign in again for official numbers."
            } else {
                lastError = "Console fetch failed — showing local estimate."
            }
            lastRefreshedAt = Date()
            logger.info(
                "OpenCode local refresh: weekly \(snap.primaryUsedPercent, format: .fixed(precision: 1))%"
            )
        } catch {
            if snapshot == nil {
                lastError = error.localizedDescription
            }
            logger.error("OpenCode local refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func currentInterval() -> TimeInterval {
        if menuIsOpen {
            return TimeInterval(settings.activePollSeconds)
        }
        return TimeInterval(settings.idlePollSeconds)
    }

    /// Keep console limit windows; attach local model/token breakdown when present.
    private static func mergeLocalModels(into server: OpenCodeSnapshot, local: OpenCodeSnapshot) -> OpenCodeSnapshot {
        var merged = server
        if !local.models.isEmpty {
            merged.models = local.models
            merged.modelsWindowLabel = local.modelsWindowLabel
            merged.inputTokens = local.inputTokens
            merged.outputTokens = local.outputTokens
            merged.cacheReadTokens = local.cacheReadTokens
            merged.cacheWriteTokens = local.cacheWriteTokens
            merged.totalSessions = local.totalSessions
        }
        return merged
    }
}
