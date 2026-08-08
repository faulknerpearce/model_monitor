import Foundation

/// Model-layer registry mapping each `MonitorProvider` to its live poller.
///
/// App wiring (start/stop all pollers, forward child changes) iterates this
/// registry instead of hardcoding each provider, so adding a provider (e.g.
/// OpenRouter) means adding one registry entry.
@MainActor
struct ProviderRegistry {
    private let pollers: [MonitorProvider: any ProviderUsagePoller]

    init(
        grok: UsagePoller,
        openCode: OpenCodeUsagePoller,
        cursor: CursorUsagePoller
    ) {
        self.pollers = [
            .grok: grok,
            .opencode: openCode,
            .cursor: cursor
        ]
    }

    var all: [(provider: MonitorProvider, poller: any ProviderUsagePoller)] {
        MonitorProvider.allCases.compactMap { provider in
            guard let poller = pollers[provider] else { return nil }
            return (provider, poller)
        }
    }

    func poller(for provider: MonitorProvider) -> (any ProviderUsagePoller)? {
        pollers[provider]
    }

    func startAll() {
        for (_, poller) in all { poller.start() }
    }

    func stopAll() {
        for (_, poller) in all { poller.stop() }
    }

    func clearAll() {
        for (_, poller) in all { poller.clearSnapshot() }
    }

    /// Pollers backing a concrete usage provider (overview excluded).
    func concretePollers() -> [any ProviderUsagePoller] {
        all.compactMap { entry in
            entry.provider == .overview ? nil : entry.poller
        }
    }
}
