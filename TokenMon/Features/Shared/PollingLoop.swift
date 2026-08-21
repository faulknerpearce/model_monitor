import Foundation

/// Shared menu-open vs idle poll interval from settings.
@MainActor
enum PollInterval {
    static func seconds(menuIsOpen: Bool, settings: AppSettings) -> TimeInterval {
        TimeInterval(menuIsOpen ? settings.activePollSeconds : settings.idlePollSeconds)
    }
}

/// Main-actor refresh loop: refreshes once immediately, then sleeps the
/// provider's returned interval between refreshes until stopped or cancelled.
@MainActor
final class PollingLoop {
    private var timerTask: Task<Void, Never>?

    private let interval: @MainActor () -> TimeInterval?
    private let refresh: @MainActor () async -> Void

    init(
        interval: @escaping @MainActor () -> TimeInterval?,
        refresh: @escaping @MainActor () async -> Void
    ) {
        self.interval = interval
        self.refresh = refresh
    }

    deinit {
        timerTask?.cancel()
    }

    func start() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                guard await self.waitUntilDue() else { return }
                guard !Task.isCancelled else { break }
                await self.refresh()
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    /// Sleeps until the next refresh is due, re-evaluating `interval()` every
    /// second so a shrinking interval (menu opened during an idle sleep) takes
    /// effect immediately instead of waiting out the full idle delay.
    private func waitUntilDue() async -> Bool {
        guard let initial = interval(), initial > 0 else { return false }
        var due = Date().addingTimeInterval(initial)
        while !Task.isCancelled {
            let remaining = due.timeIntervalSinceNow
            if remaining <= 0 { return true }
            try? await Task.sleep(nanoseconds: UInt64(min(remaining, 1) * 1_000_000_000))
            if let current = interval() {
                let candidate = Date().addingTimeInterval(current)
                if candidate < due { due = candidate }
            } else {
                return false
            }
        }
        return false
    }
}
