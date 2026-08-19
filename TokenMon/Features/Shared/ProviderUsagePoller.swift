import Combine
import Foundation

/// Uniform lifecycle surface every provider poller implements.
///
/// The Grok / OpenCode / Cursor pollers publish different typed snapshots, so
/// this protocol deliberately exposes only the shared lifecycle — start/stop and
/// a manual refresh — letting app wiring iterate over providers without guessing
/// at each poller's concrete type. Access concrete snapshots via the provider's
/// typed property on `AppModel`.
@MainActor
protocol ProviderUsagePoller: ObservableObject {
    var menuIsOpen: Bool { get set }
    func start()
    func stop()
    func refreshNow() async
    func clearSnapshot()
}
