import XCTest
import SQLite3
@testable import GrokMonitor

final class OpenCodeStatsTests: XCTestCase {
    private var dbURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grokmonitor-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("opencode.db")

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        let schema = """
        CREATE TABLE session (
            time_created INTEGER NOT NULL,
            cost REAL NOT NULL,
            tokens_input INTEGER NOT NULL,
            tokens_output INTEGER NOT NULL,
            tokens_cache_read INTEGER NOT NULL,
            tokens_cache_write INTEGER NOT NULL,
            time_archived INTEGER,
            model TEXT NOT NULL
        );
        """
        XCTAssertEqual(sqlite3_exec(db, schema, nil, nil, nil), SQLITE_OK)
    }

    override func tearDownWithError() throws {
        if let dbURL {
            try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent())
        }
        dbURL = nil
    }

    private func insert(
        timeCreated: Date,
        cost: Double,
        input: Int64,
        output: Int64 = 0,
        cacheRead: Int64 = 0,
        cacheWrite: Int64 = 0,
        model: String,
        archived: Bool = false
    ) {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO session (time_created, cost, tokens_input, tokens_output, \
        tokens_cache_read, tokens_cache_write, time_archived, model) \
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(timeCreated.timeIntervalSince1970 * 1000))
        sqlite3_bind_double(stmt, 2, cost)
        sqlite3_bind_int64(stmt, 3, input)
        sqlite3_bind_int64(stmt, 4, output)
        sqlite3_bind_int64(stmt, 5, cacheRead)
        sqlite3_bind_int64(stmt, 6, cacheWrite)
        if archived {
            sqlite3_bind_int64(stmt, 7, Int64(timeCreated.timeIntervalSince1970 * 1000))
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        sqlite3_bind_text(stmt, 8, model, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE)
    }

    private func modelJSON(provider: String, id: String) -> String {
        #"{"id":"\#(id)","providerID":"\#(provider)"}"#
    }

    func testAggregationWindowsAndModels() throws {
        let now = Date(timeIntervalSince1970: 1_785_592_600)
        let rollingStart = now.addingTimeInterval(-4 * 3600)

        insert(timeCreated: rollingStart, cost: 4, input: 10_000_000, output: 1_000_000, cacheRead: 2_000_000, model: modelJSON(provider: "opencode-go", id: "minimax-m3"))
        insert(timeCreated: rollingStart.addingTimeInterval(600), cost: 2, input: 5_000_000, cacheRead: 1_000_000, model: modelJSON(provider: "opencode-go", id: "minimax-m3"))
        insert(timeCreated: now.addingTimeInterval(-2 * 24 * 3600), cost: 90, input: 3_000_000, model: modelJSON(provider: "anthropic", id: "claude-4.5"))
        // Zen free tier must not count toward Go limits
        insert(timeCreated: rollingStart, cost: 3, input: 1_000_000, model: modelJSON(provider: "opencode", id: "deepseek-v4-flash-free"))
        insert(timeCreated: now.addingTimeInterval(-40 * 24 * 3600), cost: 500, input: 7_000_000, model: modelJSON(provider: "opencode-go", id: "kimi-k3"))
        insert(timeCreated: rollingStart, cost: 99, input: 9_000_000, model: modelJSON(provider: "opencode-go", id: "kimi-k3"), archived: true)

        let snap = try OpenCodeLocalStats.fetchSnapshot(dbURL: dbURL, now: now)

        let rolling = try XCTUnwrap(snap.windows.first { $0.kind == .rolling5h })
        XCTAssertEqual(rolling.usedUSD, 6, accuracy: 0.001)
        XCTAssertEqual(rolling.sessionCount, 2)
        XCTAssertEqual(rolling.usedPercent, 50, accuracy: 0.01)

        let week = try XCTUnwrap(snap.windows.first { $0.kind == .weekly })
        XCTAssertEqual(week.usedUSD, 6, accuracy: 0.001)
        XCTAssertEqual(week.sessionCount, 2)

        // Monthly is subscription-anchored to earliest Go session (−40d). That
        // session itself falls outside the current billing month, so only the
        // recent Go sessions count.
        let month = try XCTUnwrap(snap.windows.first { $0.kind == .monthly })
        XCTAssertEqual(month.usedUSD, 6, accuracy: 0.001)
        XCTAssertEqual(month.sessionCount, 2)

        // Model list still shows activity in the window (includes Zen).
        XCTAssertGreaterThanOrEqual(snap.models.count, 1)
        let goModel = try XCTUnwrap(snap.models.first { $0.providerID == "opencode-go" && $0.modelID == "minimax-m3" })
        XCTAssertEqual(goModel.sessionCount, 2)
        XCTAssertEqual(goModel.inputTokens, 15_000_000)
        XCTAssertEqual(goModel.outputTokens, 1_000_000)
        XCTAssertEqual(goModel.cacheReadTokens, 3_000_000)
        XCTAssertEqual(goModel.costUSD, 6, accuracy: 0.001)

        XCTAssertEqual(snap.modelsWindowLabel, "All models this week")
        let topModel = try XCTUnwrap(snap.models.first)
        XCTAssertEqual(topModel.modelID, "claude-4.5")
        XCTAssertEqual(topModel.costUSD, 90, accuracy: 0.001)
        // Menu bar prefers weekly (6/30), not rolling 5h (6/12).
        XCTAssertEqual(snap.primaryUsedPercent, 20, accuracy: 0.01)

        // Zen activity still appears in the model list when used.
        XCTAssertNotNil(snap.models.first { $0.providerID == "opencode" && $0.modelID == "deepseek-v4-flash-free" })
    }

    func testZenDoesNotCountTowardGoLimits() throws {
        let now = Date(timeIntervalSince1970: 1_785_592_600)
        insert(timeCreated: now.addingTimeInterval(-3600), cost: 8, input: 1, model: modelJSON(provider: "opencode", id: "free-model"))
        insert(timeCreated: now.addingTimeInterval(-1800), cost: 1, input: 1, model: modelJSON(provider: "opencode-go", id: "minimax-m3"))

        let snap = try OpenCodeLocalStats.fetchSnapshot(dbURL: dbURL, now: now)
        let rolling = try XCTUnwrap(snap.windows.first { $0.kind == .rolling5h })
        XCTAssertEqual(rolling.usedUSD, 1, accuracy: 0.001)
        XCTAssertEqual(rolling.sessionCount, 1)
        XCTAssertEqual(rolling.usedPercent, 1 / 12 * 100, accuracy: 0.01)
    }

    func testRollingResetTracksLastEligibleSession() throws {
        let now = Date(timeIntervalSince1970: 1_785_592_600)
        let last = now.addingTimeInterval(-3600)

        insert(timeCreated: now.addingTimeInterval(-4 * 3600), cost: 1, input: 1, model: modelJSON(provider: "opencode-go", id: "m"))
        insert(timeCreated: last, cost: 1, input: 1, model: modelJSON(provider: "opencode-go", id: "m"))
        // Zen activity should not drive the Go rolling reset clock
        insert(timeCreated: now.addingTimeInterval(-600), cost: 5, input: 1, model: modelJSON(provider: "opencode", id: "free"))

        let snap = try OpenCodeLocalStats.fetchSnapshot(dbURL: dbURL, now: now)
        let rolling = try XCTUnwrap(snap.windows.first { $0.kind == .rolling5h })
        let resetsAt = try XCTUnwrap(rolling.resetsAt)
        XCTAssertEqual(resetsAt.timeIntervalSince1970, last.timeIntervalSince1970 + 5 * 3600, accuracy: 1)
    }

    func testModelsUseWeeklyWindow() throws {
        let now = Date(timeIntervalSince1970: 1_785_592_600)
        insert(timeCreated: now.addingTimeInterval(-3 * 24 * 3600), cost: 2, input: 1, model: modelJSON(provider: "opencode-go", id: "m"))

        let snap = try OpenCodeLocalStats.fetchSnapshot(dbURL: dbURL, now: now)
        XCTAssertEqual(snap.modelsWindowLabel, "All models this week")
        XCTAssertEqual(snap.models.count, 1)
        XCTAssertEqual(snap.primaryUsedPercent, 2.0 / 30.0 * 100, accuracy: 0.01)
    }

    func testDatabaseMissingThrows() {
        XCTAssertThrowsError(try OpenCodeLocalStats.fetchSnapshot(dbURL: dbURL.appendingPathComponent("nope.db")))
    }

    func testClampedPercent() {
        XCTAssertEqual(OpenCodeWindowUsage.clampedPercent(usedUSD: 6, limitUSD: 12), 50, accuracy: 0.01)
        XCTAssertEqual(OpenCodeWindowUsage.clampedPercent(usedUSD: 15, limitUSD: 12), 100, accuracy: 0.01)
        XCTAssertEqual(OpenCodeWindowUsage.clampedPercent(usedUSD: 0, limitUSD: 12), 0, accuracy: 0.01)
        XCTAssertEqual(OpenCodeWindowUsage.clampedPercent(usedUSD: 3, limitUSD: 0), 0, accuracy: 0.01)
    }

    func testWindowLabelsAndLimits() {
        XCTAssertEqual(OpenCodeWindowKind.rolling5h.label, "5-Hour")
        XCTAssertEqual(OpenCodeWindowKind.weekly.label, "Weekly")
        XCTAssertEqual(OpenCodeWindowKind.monthly.label, "Monthly")
        XCTAssertEqual(OpenCodeWindowKind.rolling5h.defaultLimitUSD, 12)
        XCTAssertEqual(OpenCodeWindowKind.weekly.defaultLimitUSD, 30)
        XCTAssertEqual(OpenCodeWindowKind.monthly.defaultLimitUSD, 60)
    }

    func testWeeklyBoundsUTCMonday() throws {
        // Wednesday 2026-07-15 13:00 UTC → week Mon 2026-07-13 00:00 UTC … Mon 2026-07-20
        let now = Date(timeIntervalSince1970: 1_784_120_400) // 2026-07-15 13:00:00 UTC
        let week = OpenCodeLocalStats.weeklyBounds(now: now)
        XCTAssertEqual(week.start.timeIntervalSince1970, 1_783_900_800, accuracy: 1) // 2026-07-13 00:00 UTC
        XCTAssertEqual(week.end.timeIntervalSince(week.start), 7 * 24 * 3600, accuracy: 1)

        // Sunday should still roll back to prior Monday
        let sunday = Date(timeIntervalSince1970: 1_784_462_400) // 2026-07-19 12:00 UTC (Sunday)
        let weekSun = OpenCodeLocalStats.weeklyBounds(now: sunday)
        XCTAssertEqual(weekSun.start.timeIntervalSince1970, 1_783_900_800, accuracy: 1)
    }

    func testMonthlyBoundsSubscriptionAnchored() throws {
        // Subscribed 2026-05-18 14:24:41 UTC; "now" is 2026-08-01 15:00 UTC
        let subscribed = Date(timeIntervalSince1970: 1_779_114_281)
        let now = Date(timeIntervalSince1970: 1_785_596_400)
        let month = OpenCodeLocalStats.monthlyBounds(now: now, subscribedAt: subscribed)

        // Period should be 2026-07-18 14:24:41 … 2026-08-18 14:24:41 (not calendar Aug 1)
        XCTAssertEqual(month.start.timeIntervalSince1970, 1_784_384_681, accuracy: 2)
        XCTAssertEqual(month.end.timeIntervalSince1970, 1_787_063_081, accuracy: 2)
        XCTAssertLessThan(month.start, now)
        XCTAssertGreaterThan(month.end, now)
    }

    func testMonthlyAggregationUsesSubscriptionWindow() throws {
        // Subscribed via first Go session on 2026-05-18; "now" is 2026-08-01 15:00 UTC
        // → billing month 2026-07-18 … 2026-08-18
        let now = Date(timeIntervalSince1970: 1_785_596_400)
        let subscribed = Date(timeIntervalSince1970: 1_779_114_281)
        let inMonth = Date(timeIntervalSince1970: 1_784_500_000) // ~2026-07-19
        let beforeMonth = Date(timeIntervalSince1970: 1_784_000_000) // ~2026-07-13

        insert(timeCreated: subscribed, cost: 1, input: 1, model: modelJSON(provider: "opencode-go", id: "m"))
        insert(timeCreated: beforeMonth, cost: 20, input: 1, model: modelJSON(provider: "opencode-go", id: "m"))
        insert(timeCreated: inMonth, cost: 7, input: 1, model: modelJSON(provider: "opencode-go", id: "m"))
        insert(timeCreated: now.addingTimeInterval(-3600), cost: 3, input: 1, model: modelJSON(provider: "opencode-go", id: "m"))

        let snap = try OpenCodeLocalStats.fetchSnapshot(dbURL: dbURL, now: now)
        let month = try XCTUnwrap(snap.windows.first { $0.kind == .monthly })
        XCTAssertEqual(month.usedUSD, 10, accuracy: 0.001) // 7 + 3, not calendar-month $3
        XCTAssertEqual(month.sessionCount, 2)
        // Must not reset at calendar month start (would leave only $3)
        XCTAssertNotEqual(month.usedUSD, 3, accuracy: 0.001)
    }

    func testMonthlyBoundsClampsShortMonths() throws {
        // Subscribed on Jan 31 → period through Feb clamps end day to Feb 28 (2026 not leap)
        let subscribed = Date(timeIntervalSince1970: 1_769_817_600) // 2026-01-31 00:00 UTC
        let now = Date(timeIntervalSince1970: 1_771_113_600) // 2026-02-15 00:00 UTC
        let month = OpenCodeLocalStats.monthlyBounds(now: now, subscribedAt: subscribed)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(cal.component(.month, from: month.start), 1)
        XCTAssertEqual(cal.component(.day, from: month.start), 31)
        XCTAssertEqual(cal.component(.month, from: month.end), 2)
        XCTAssertEqual(cal.component(.day, from: month.end), 28)
    }

    func testGoEligibleProvider() {
        XCTAssertTrue(OpenCodeLocalStats.goEligibleProvider("opencode-go"))
        XCTAssertTrue(OpenCodeLocalStats.goEligibleProvider("OpenCode-Go"))
        XCTAssertFalse(OpenCodeLocalStats.goEligibleProvider("opencode"))
        XCTAssertFalse(OpenCodeLocalStats.goEligibleProvider("anthropic"))
        XCTAssertFalse(OpenCodeLocalStats.goEligibleProvider("deepseek"))
    }

    func testCatalogNames() {
        XCTAssertEqual(OpenCodeCatalog.providerShortName("opencode-go"), "Go")
        XCTAssertEqual(OpenCodeCatalog.providerShortName("opencode"), "Zen")
        XCTAssertEqual(OpenCodeCatalog.providerShortName("deepseek"), "DeepSeek")
        XCTAssertEqual(OpenCodeCatalog.modelDisplayName(providerID: "deepseek", modelID: "deepseek-v4-pro"), "DeepSeek · deepseek-v4-pro")
    }

    func testModelPaletteDeterministic() {
        let a = ModelPalette.sRGB(for: "deepseek/deepseek-v4-pro")
        let b = ModelPalette.sRGB(for: "deepseek/deepseek-v4-pro")
        XCTAssertEqual(a.red, b.red)
        XCTAssertEqual(a.green, b.green)
        XCTAssertEqual(a.blue, b.blue)
        XCTAssertTrue(a.red >= 0 && a.red <= 1)
        XCTAssertTrue(a.green >= 0 && a.green <= 1)
        XCTAssertTrue(a.blue >= 0 && a.blue <= 1)
    }

    func testModelPaletteProviderColors() {
        let go = ModelPalette.sRGB(forProvider: "opencode-go", seed: "x")
        XCTAssertEqual(go.red, ModelPalette.goOrange.red, accuracy: 0.001)
        XCTAssertEqual(go.green, ModelPalette.goOrange.green, accuracy: 0.001)
        XCTAssertEqual(go.blue, ModelPalette.goOrange.blue, accuracy: 0.001)

        let zen = ModelPalette.sRGB(forProvider: "opencode", seed: "x")
        XCTAssertEqual(zen.red, ModelPalette.zenBlue.red, accuracy: 0.001)
        XCTAssertEqual(zen.green, ModelPalette.zenBlue.green, accuracy: 0.001)
        XCTAssertEqual(zen.blue, ModelPalette.zenBlue.blue, accuracy: 0.001)
    }

    func testUnusedModelsExcludedFromList() throws {
        let now = Date(timeIntervalSince1970: 1_785_592_600)
        insert(timeCreated: now.addingTimeInterval(-3600), cost: 2, input: 100, model: modelJSON(provider: "opencode-go", id: "used"))
        insert(timeCreated: now.addingTimeInterval(-1800), cost: 0, input: 0, output: 0, model: modelJSON(provider: "opencode-go", id: "empty"))

        let snap = try OpenCodeLocalStats.fetchSnapshot(dbURL: dbURL, now: now)
        XCTAssertEqual(snap.models.count, 1)
        XCTAssertEqual(snap.models.first?.modelID, "used")
    }

    func testWeekHeatmapAggregatesByDayAndModel() throws {
        // Wednesday 2026-07-15 13:00 UTC → week Mon 2026-07-13 … Mon 2026-07-20
        let now = Date(timeIntervalSince1970: 1_784_120_400)
        let monday = Date(timeIntervalSince1970: 1_783_900_800) // 2026-07-13 00:00 UTC
        let tuesday = monday.addingTimeInterval(24 * 3600)
        let wednesday = monday.addingTimeInterval(2 * 24 * 3600)

        insert(timeCreated: monday.addingTimeInterval(3600), cost: 3, input: 1, model: modelJSON(provider: "opencode-go", id: "minimax-m3"))
        insert(timeCreated: tuesday.addingTimeInterval(3600), cost: 1, input: 1, model: modelJSON(provider: "opencode-go", id: "minimax-m3"))
        insert(timeCreated: wednesday.addingTimeInterval(3600), cost: 5, input: 1, model: modelJSON(provider: "opencode", id: "zen-free"))
        insert(timeCreated: now.addingTimeInterval(-40 * 24 * 3600), cost: 9, input: 1, model: modelJSON(provider: "opencode-go", id: "old"))

        let heat = try OpenCodeLocalStats.fetchWeekHeatmap(dbURL: dbURL, now: now)
        XCTAssertEqual(heat.dayLabels.count, 7)
        XCTAssertEqual(heat.rows.count, 2)

        let go = try XCTUnwrap(heat.rows.first { $0.modelID == "minimax-m3" })
        XCTAssertEqual(go.dayValues[0], 3, accuracy: 0.001) // Monday
        XCTAssertEqual(go.dayValues[1], 1, accuracy: 0.001) // Tuesday
        XCTAssertEqual(go.weekTotal, 4, accuracy: 0.001)

        let zen = try XCTUnwrap(heat.rows.first { $0.modelID == "zen-free" })
        XCTAssertEqual(zen.dayValues[2], 5, accuracy: 0.001) // Wednesday
        XCTAssertFalse(heat.rows.contains { $0.modelID == "old" })
    }

    func testPreviewSnapshot() {
        let preview = OpenCodeSnapshot.preview
        XCTAssertEqual(preview.windows.count, 3)
        XCTAssertEqual(preview.windows.first?.kind, .rolling5h)
        XCTAssertEqual(preview.modelsWindowLabel, "All models this week")
        XCTAssertEqual(preview.primaryUsedPercent, 12.4 / 30 * 100, accuracy: 0.01)
        XCTAssertGreaterThan(preview.inputTokens, 0)
    }
}
