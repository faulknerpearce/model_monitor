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
                guard let delay = self.interval(), delay > 0 else { return }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self.refresh()
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }
}
