import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var showCategoriesInMenuBar: Bool {
        didSet {
            guard showCategoriesInMenuBar != oldValue else { return }
            defaults.set(showCategoriesInMenuBar, forKey: Keys.showCategories)
        }
    }

    /// Grok segmented bar in the menu bar.
    @Published var showGrokBarInMenuBar: Bool {
        didSet {
            guard showGrokBarInMenuBar != oldValue else { return }
            defaults.set(showGrokBarInMenuBar, forKey: Keys.showGrokBar)
        }
    }

    /// OpenCode usage % + bar in the menu bar.
    @Published var showOpenCodeBarInMenuBar: Bool {
        didSet {
            guard showOpenCodeBarInMenuBar != oldValue else { return }
            defaults.set(showOpenCodeBarInMenuBar, forKey: Keys.showOpenCodeBar)
        }
    }

    /// Cursor usage % + bar in the menu bar.
    @Published var showCursorBarInMenuBar: Bool {
        didSet {
            guard showCursorBarInMenuBar != oldValue else { return }
            defaults.set(showCursorBarInMenuBar, forKey: Keys.showCursorBar)
        }
    }

    @Published var activePollSeconds: Int {
        didSet {
            let clamped = Self.clampActivePoll(activePollSeconds)
            if activePollSeconds != clamped { activePollSeconds = clamped }
            defaults.set(activePollSeconds, forKey: Keys.activePoll)
        }
    }

    @Published var idlePollSeconds: Int {
        didSet {
            let clamped = Self.clampIdlePoll(idlePollSeconds)
            if idlePollSeconds != clamped { idlePollSeconds = clamped }
            defaults.set(idlePollSeconds, forKey: Keys.idlePoll)
        }
    }

    @Published var thresholdEnabled: Bool {
        didSet { defaults.set(thresholdEnabled, forKey: Keys.thresholdEnabled) }
    }

    @Published var thresholdPercent: Double {
        didSet { defaults.set(thresholdPercent, forKey: Keys.thresholdPercent) }
    }

    @Published var visibleProductIDs: Set<String> {
        didSet {
            defaults.set(Array(visibleProductIDs), forKey: Keys.visibleProducts)
        }
    }

    @Published var selectedProvider: MonitorProvider {
        didSet {
            guard selectedProvider != oldValue else { return }
            defaults.set(selectedProvider.rawValue, forKey: Keys.selectedProvider)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isRevertingLaunchAtLogin, launchAtLogin != oldValue else { return }
            updateLaunchAtLogin()
        }
    }

    /// Whether Grok should be polled (panel tab or menu-bar graph).
    var needsGrokPolling: Bool {
        selectedProvider.pollsGrok || showGrokBarInMenuBar
    }

    /// Whether OpenCode should be polled (panel tab or menu-bar graph).
    var needsOpenCodePolling: Bool {
        selectedProvider.pollsOpenCode || showOpenCodeBarInMenuBar
    }

    /// Whether Cursor should be polled (panel tab or menu-bar graph).
    var needsCursorPolling: Bool {
        selectedProvider.pollsCursor || showCursorBarInMenuBar
    }

    /// Guards against recursive `didSet` when registration fails and we revert.
    private var isRevertingLaunchAtLogin = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showCategoriesInMenuBar = defaults.object(forKey: Keys.showCategories) as? Bool ?? true
        showGrokBarInMenuBar = defaults.object(forKey: Keys.showGrokBar) as? Bool ?? true
        showOpenCodeBarInMenuBar = defaults.object(forKey: Keys.showOpenCodeBar) as? Bool ?? false
        showCursorBarInMenuBar = defaults.object(forKey: Keys.showCursorBar) as? Bool ?? false
        // Clamp on load — didSet does not run during init.
        activePollSeconds = Self.clampActivePoll(defaults.object(forKey: Keys.activePoll) as? Int ?? 60)
        idlePollSeconds = Self.clampIdlePoll(defaults.object(forKey: Keys.idlePoll) as? Int ?? 300)
        thresholdEnabled = defaults.object(forKey: Keys.thresholdEnabled) as? Bool ?? true
        thresholdPercent = defaults.object(forKey: Keys.thresholdPercent) as? Double ?? 80
        selectedProvider = MonitorProvider(rawValue: defaults.string(forKey: Keys.selectedProvider) ?? "") ?? .grok
        if let saved = defaults.stringArray(forKey: Keys.visibleProducts) {
            visibleProductIDs = Set(saved.map { $0.lowercased() })
        } else {
            visibleProductIDs = Set(ProductCatalog.knownIDs)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private static func clampActivePoll(_ value: Int) -> Int { max(15, min(300, value)) }
    private static func clampIdlePoll(_ value: Int) -> Int { max(15, min(3600, value)) }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert UI if registration fails (e.g. unsigned debug builds).
            let actual = SMAppService.mainApp.status == .enabled
            guard launchAtLogin != actual else { return }
            isRevertingLaunchAtLogin = true
            launchAtLogin = actual
            isRevertingLaunchAtLogin = false
        }
    }

    private enum Keys {
        static let showCategories = "showCategoriesInMenuBar"
        static let showGrokBar = "showGrokBarInMenuBar"
        static let showOpenCodeBar = "showOpenCodeBarInMenuBar"
        static let showCursorBar = "showCursorBarInMenuBar"
        static let activePoll = "activePollSeconds"
        static let idlePoll = "idlePollSeconds"
        static let thresholdEnabled = "thresholdEnabled"
        static let thresholdPercent = "thresholdPercent"
        static let selectedProvider = "selectedProvider"
        static let visibleProducts = "visibleProductIDs"
    }
}
