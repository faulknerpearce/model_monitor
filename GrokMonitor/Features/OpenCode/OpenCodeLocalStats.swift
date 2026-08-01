import Foundation
import SQLite3

enum OpenCodeLocalStatsError: LocalizedError {
    case databaseMissing(URL)
    case openFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case let .databaseMissing(url):
            return "OpenCode usage database not found at \(url.path). Install and use OpenCode to track usage."
        case let .openFailed(message):
            return "Could not open the OpenCode usage database: \(message)"
        case let .queryFailed(message):
            return "Could not read OpenCode usage: \(message)"
        }
    }
}

enum OpenCodeLocalStats {
    static let rolling5hSeconds: TimeInterval = 5 * 3600

    /// Real user home, not the sandbox container home (`NSHomeDirectory` would
    /// resolve to the app container).
    static var realHomeDirectory: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    static var databaseDirectory: URL {
        realHomeDirectory
            .appendingPathComponent(".local/share/opencode", isDirectory: true)
    }

    static var databaseURL: URL {
        databaseDirectory.appendingPathComponent("opencode.db")
    }

    /// OpenCode Go subscription usage only (`opencode-go`). Zen (`opencode`)
    /// and direct provider keys do not count toward Go $12 / $30 / $60 limits.
    static func goEligibleProvider(_ providerID: String) -> Bool {
        providerID.lowercased() == "opencode-go"
    }

    /// UTC Monday–Sunday week, matching OpenCode server `getWeekBounds`.
    static func weeklyBounds(now: Date = Date()) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let utcNow = now
        let day = calendar.component(.weekday, from: utcNow) // 1=Sun … 7=Sat
        // Convert to Monday-based offset: Mon=0 … Sun=6
        let offset = (day + 5) % 7
        let startOfDay = calendar.startOfDay(for: utcNow)
        let start = calendar.date(byAdding: .day, value: -offset, to: startOfDay) ?? startOfDay
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return (start, end)
    }

    /// Subscription-anchored month, matching OpenCode server `getMonthlyBounds(now, subscribed)`.
    /// `subscribedAt` is the Go plan start (UTC components of that instant).
    static func monthlyBounds(now: Date = Date(), subscribedAt: Date) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let day = calendar.component(.day, from: subscribedAt)
        let hour = calendar.component(.hour, from: subscribedAt)
        let minute = calendar.component(.minute, from: subscribedAt)
        let second = calendar.component(.second, from: subscribedAt)
        let nanosecond = calendar.component(.nanosecond, from: subscribedAt)

        func anchor(year: Int, month: Int) -> Date {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            let maxDay = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? now)?.count ?? 28
            comps.day = min(day, maxDay)
            comps.hour = hour
            comps.minute = minute
            comps.second = second
            comps.nanosecond = nanosecond
            return calendar.date(from: comps) ?? now
        }

        func shift(year: Int, month: Int, delta: Int) -> (Int, Int) {
            let total = year * 12 + (month - 1) + delta
            let y = Int(floor(Double(total) / 12.0))
            let m = ((total % 12) + 12) % 12 + 1
            return (y, m)
        }

        var y = calendar.component(.year, from: now)
        var m = calendar.component(.month, from: now)
        var start = anchor(year: y, month: m)
        if start > now {
            (y, m) = shift(year: y, month: m, delta: -1)
            start = anchor(year: y, month: m)
        }
        let (ny, nm) = shift(year: y, month: m, delta: 1)
        let end = anchor(year: ny, month: nm)
        return (start, end)
    }

    struct SessionRow: Sendable {
        var timeCreatedMS: Int64
        var costUSD: Double
        var inputTokens: Int64
        var outputTokens: Int64
        var cacheReadTokens: Int64
        var cacheWriteTokens: Int64
        var providerID: String
        var modelID: String
    }

    static func fetchSnapshot(now: Date = Date()) throws -> OpenCodeSnapshot {
        try fetchSnapshot(dbURL: databaseURL, now: now)
    }

    static func fetchSnapshot(dbURL: URL, now: Date = Date()) throws -> OpenCodeSnapshot {
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw OpenCodeLocalStatsError.databaseMissing(dbURL)
        }
        let rows = try readRows(from: dbURL)

        let rollingStart = now.addingTimeInterval(-rolling5hSeconds)
        let week = weeklyBounds(now: now)
        let subscribedAt = earliestGoSessionDate(in: rows) ?? now
        let month = monthlyBounds(now: now, subscribedAt: subscribedAt)

        let rollingRows = rows.filter { $0.timeCreatedMS >= Int64(rollingStart.timeIntervalSince1970 * 1000) }
        let weekRows = rows.filter { inWindow($0, start: week.start, end: week.end) }
        let monthRows = rows.filter { inWindow($0, start: month.start, end: month.end) }

        let rollingUsage = windowUsage(kind: .rolling5h, rows: rollingRows, limitUSD: 12, resetsAt: rollingReset(rows: rollingRows, now: now))
        let weekUsage = windowUsage(kind: .weekly, rows: weekRows, limitUSD: 30, resetsAt: week.end)
        let monthUsage = windowUsage(kind: .monthly, rows: monthRows, limitUSD: 60, resetsAt: month.end)

        // Model breakdown follows the weekly view rather than switching to the
        // shorter rolling window whenever there is recent activity.
        let modelWindow = weekRows
        let models = modelUsage(rows: modelWindow)

        let totals = tokenTotals(rows: modelWindow)

        return OpenCodeSnapshot(
            fetchedAt: now,
            windows: [rollingUsage, weekUsage, monthUsage],
            models: models,
            modelsWindowLabel: "All models this week",
            inputTokens: totals.input,
            outputTokens: totals.output,
            cacheReadTokens: totals.cacheRead,
            cacheWriteTokens: totals.cacheWrite,
            totalSessions: modelWindow.count,
            isEstimated: true
        )
    }

    private static func earliestGoSessionDate(in rows: [SessionRow]) -> Date? {
        rows
            .filter { goEligibleProvider($0.providerID) }
            .map { Date(timeIntervalSince1970: TimeInterval($0.timeCreatedMS) / 1000) }
            .min()
    }

    private static func inWindow(_ row: SessionRow, start: Date, end: Date) -> Bool {
        let time = Date(timeIntervalSince1970: TimeInterval(row.timeCreatedMS) / 1000)
        return time >= start && time < end
    }

    private static func windowUsage(kind: OpenCodeWindowKind, rows: [SessionRow], limitUSD: Double, resetsAt: Date?) -> OpenCodeWindowUsage {
        let eligible = rows.filter { goEligibleProvider($0.providerID) }
        let used = eligible.reduce(0) { $0 + $1.costUSD }
        return OpenCodeWindowUsage(
            kind: kind,
            usedUSD: used,
            limitUSD: limitUSD,
            resetsAt: resetsAt,
            sessionCount: eligible.count
        )
    }

    private static func rollingReset(rows: [SessionRow], now: Date) -> Date? {
        let eligible = rows.filter { goEligibleProvider($0.providerID) }
        // Match server-style reset: last Go activity in the window + rolling duration.
        guard let last = eligible.map({ Date(timeIntervalSince1970: TimeInterval($0.timeCreatedMS) / 1000) }).max() else {
            return nil
        }
        return last.addingTimeInterval(rolling5hSeconds)
    }

    private static func modelUsage(rows: [SessionRow]) -> [OpenCodeModelUsage] {
        var byKey: [String: OpenCodeModelUsage] = [:]
        for row in rows {
            let key = "\(row.providerID)/\(row.modelID)"
            var usage = byKey[key] ?? OpenCodeModelUsage(
                providerID: row.providerID,
                modelID: row.modelID,
                sessionCount: 0,
                inputTokens: 0,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheWriteTokens: 0,
                costUSD: 0,
                percentOfWindow: 0
            )
            usage.sessionCount += 1
            usage.inputTokens += row.inputTokens
            usage.outputTokens += row.outputTokens
            usage.cacheReadTokens += row.cacheReadTokens
            usage.cacheWriteTokens += row.cacheWriteTokens
            usage.costUSD += row.costUSD
            byKey[key] = usage
        }
        let used = byKey.values.filter { usage in
            usage.sessionCount > 0
                && (usage.costUSD > 0
                    || usage.inputTokens > 0
                    || usage.outputTokens > 0
                    || usage.cacheReadTokens > 0
                    || usage.cacheWriteTokens > 0)
        }
        let totalCost = used.reduce(0) { $0 + $1.costUSD }
        return used
            .sorted { a, b in
                if a.costUSD != b.costUSD { return a.costUSD > b.costUSD }
                return a.outputTokens > b.outputTokens
            }
            .map { usage in
                var copy = usage
                copy.percentOfWindow = totalCost > 0 ? copy.costUSD / totalCost * 100 : 0
                return copy
            }
    }

    private static func tokenTotals(rows: [SessionRow]) -> (input: Int64, output: Int64, cacheRead: Int64, cacheWrite: Int64) {
        var input: Int64 = 0
        var output: Int64 = 0
        var cacheRead: Int64 = 0
        var cacheWrite: Int64 = 0
        for row in rows {
            input += row.inputTokens
            output += row.outputTokens
            cacheRead += row.cacheReadTokens
            cacheWrite += row.cacheWriteTokens
        }
        return (input, output, cacheRead, cacheWrite)
    }

    private static func readRows(from dbURL: URL) throws -> [SessionRow] {
        var db: OpaquePointer?
        // URI + readonly so concurrent OpenCode WAL writers remain readable.
        let uri = "file:\(dbURL.path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            throw OpenCodeLocalStatsError.openFailed(message)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)

        let sql = """
        SELECT time_created, cost, tokens_input, tokens_output, \
        tokens_cache_read, tokens_cache_write, model \
        FROM session WHERE time_archived IS NULL
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw OpenCodeLocalStatsError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var rows: [SessionRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let (providerID, modelID) = modelParts(sqlite3_column_text(stmt, 6))
            rows.append(SessionRow(
                timeCreatedMS: sqlite3_column_int64(stmt, 0),
                costUSD: sqlite3_column_double(stmt, 1),
                inputTokens: sqlite3_column_int64(stmt, 2),
                outputTokens: sqlite3_column_int64(stmt, 3),
                cacheReadTokens: sqlite3_column_int64(stmt, 4),
                cacheWriteTokens: sqlite3_column_int64(stmt, 5),
                providerID: providerID,
                modelID: modelID
            ))
        }
        return rows
    }

    private static func modelParts(_ text: UnsafePointer<UInt8>?) -> (providerID: String, modelID: String) {
        guard let text,
              let data = String(cString: text).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ("other", "unknown")
        }
        let modelID = json["id"] as? String ?? "unknown"
        let providerID = json["providerID"] as? String ?? "other"
        return (providerID, modelID)
    }
}
