@testable import TokenMon
import XCTest

/// AppSettings clamps, persistence keys, and needs*Polling gating —
/// all against an isolated UserDefaults suite.
@MainActor
final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "AppSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeSettings() -> AppSettings {
        AppSettings(defaults: defaults)
    }

    func testActivePollClampedToMinimum() throws {
        let settings = makeSettings()
        settings.activePollSeconds = 1
        XCTAssertEqual(settings.activePollSeconds, 15)
    }

    func testActivePollClampedToMaximum() throws {
        let settings = makeSettings()
        settings.activePollSeconds = 10_000
        XCTAssertEqual(settings.activePollSeconds, 300)
    }

    func testIdlePollClamped() throws {
        let settings = makeSettings()
        settings.idlePollSeconds = 0
        XCTAssertEqual(settings.idlePollSeconds, 15)
        settings.idlePollSeconds = 100_000
        XCTAssertEqual(settings.idlePollSeconds, 3600)
    }

    func testValuesPersistAcrossInstances() throws {
        let first = makeSettings()
        first.activePollSeconds = 45
        first.showCursorBarInMenuBar = true
        first.showClaudeBarInMenuBar = true

        let second = makeSettings()
        XCTAssertEqual(second.activePollSeconds, 45)
        XCTAssertTrue(second.showCursorBarInMenuBar)
        XCTAssertTrue(second.showClaudeBarInMenuBar)
    }

    func testNeedsGrokPollingFollowsBarAndProvider() {
        let settings = makeSettings()
        settings.selectedProvider = .cursor
        settings.showGrokBarInMenuBar = false
        XCTAssertFalse(settings.needsGrokPolling)

        settings.showGrokBarInMenuBar = true
        XCTAssertTrue(settings.needsGrokPolling)

        settings.showGrokBarInMenuBar = false
        settings.selectedProvider = .grok
        XCTAssertTrue(settings.needsGrokPolling)
    }

    func testNeedsOpenCodeAndCursorPollingOnOverview() {
        let settings = makeSettings()
        settings.selectedProvider = .overview
        XCTAssertTrue(settings.needsOpenCodePolling)
        XCTAssertTrue(settings.needsCursorPolling)
        XCTAssertTrue(settings.needsGrokPolling)
    }

    func testNeedsPollingOffWhenBarsHiddenAndOtherTabSelected() {
        let settings = makeSettings()
        settings.selectedProvider = .grok
        settings.showCursorBarInMenuBar = false
        settings.showOpenCodeBarInMenuBar = false
        XCTAssertFalse(settings.needsCursorPolling)
        XCTAssertFalse(settings.needsOpenCodePolling)
    }

    func testNeedsClaudePollingFollowsBarAndProvider() {
        let settings = makeSettings()
        settings.selectedProvider = .cursor
        settings.showClaudeBarInMenuBar = false
        XCTAssertFalse(settings.needsClaudePolling)

        settings.showClaudeBarInMenuBar = true
        XCTAssertTrue(settings.needsClaudePolling)

        settings.showClaudeBarInMenuBar = false
        settings.selectedProvider = .claude
        XCTAssertTrue(settings.needsClaudePolling)
    }

    // MARK: - Provider visibility

    func testEnabledProvidersDefaultToAllUsageProviders() {
        let settings = makeSettings()
        XCTAssertEqual(settings.enabledProviderIDs, Set(MonitorProvider.usageProviders))
        XCTAssertEqual(settings.visibleUsageProviders, MonitorProvider.usageProviders)
    }

    func testVisibleUsageProvidersFollowUsageProviderOrder() {
        let settings = makeSettings()
        settings.enabledProviderIDs = [.opencode, .grok]
        XCTAssertEqual(settings.visibleUsageProviders, [.grok, .opencode])
    }

    func testEnabledProvidersPersistAcrossInstances() throws {
        let first = makeSettings()
        first.enabledProviderIDs = [.grok, .cursor]

        let second = makeSettings()
        XCTAssertEqual(second.enabledProviderIDs, [.grok, .cursor])
        XCTAssertEqual(second.visibleUsageProviders, [.grok, .cursor])
    }

    func testCannotRemoveLastEnabledProvider() {
        let settings = makeSettings()
        settings.enabledProviderIDs = [.cursor]

        settings.enabledProviderIDs = []

        XCTAssertEqual(settings.enabledProviderIDs, [.cursor])
    }

    func testStoredOverviewAndUnknownValuesAreIgnored() {
        defaults.set(["overview", "gemini", "copilot"], forKey: "enabledProviderIDs")
        let settings = makeSettings()
        XCTAssertEqual(settings.enabledProviderIDs, Set(MonitorProvider.usageProviders))
    }

    func testStoredValidSubsetSurvivesLoad() {
        defaults.set(["opencode", "overview"], forKey: "enabledProviderIDs")
        let settings = makeSettings()
        XCTAssertEqual(settings.enabledProviderIDs, [.opencode])
    }
}
