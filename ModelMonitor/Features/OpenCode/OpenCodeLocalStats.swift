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

    /// Go or Zen plan providers shown in the OpenCode models list / heatmap.
    /// Direct BYOK keys (`deepseek`, `xai`, `openai`, …) are excluded.
    static func planEligibleProvider(_ providerID: String) -> Bool {
        switch providerID.lowercased() {
        case "opencode-go", "opencode": return true
        default: return false
        }
    }

    /// Grok used through the OpenCode harness (counts toward Overview Grok, not OpenCode).
    static func grokViaOpenCode(providerID: String, modelID: String = "") -> Bool {
        let provider = providerID.lowercased()
        if provider == "xai" { return true }
        return modelID.lowercased().contains("grok")
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
        /// Present for message-level rows; empty for session-table rows.
        var sessionID: String = ""
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

        // Model breakdown from assistant messages so mid-session model switches are counted.
        let modelEvents = try readAssistantMessageRows(
            from: dbURL,
            startMS: Int64(week.start.timeIntervalSince1970 * 1000),
            endMS: Int64(week.end.timeIntervalSince1970 * 1000)
        )
        let planEvents = modelEvents.filter { planEligibleProvider($0.providerID) }
        let models = modelUsage(rows: planEvents)
        let totals = tokenTotals(rows: planEvents)

        let monthEvents = try readAssistantMessageRows(
            from: dbURL,
            startMS: Int64(month.start.timeIntervalSince1970 * 1000),
            endMS: Int64(month.end.timeIntervalSince1970 * 1000)
        )
        .filter { planEligibleProvider($0.providerID) }
        let monthTotals = tokenTotals(rows: monthEvents)
        let monthEstimated = estimatedCostUSD(rows: monthEvents)

        return OpenCodeSnapshot(
            fetchedAt: now,
            windows: [rollingUsage, weekUsage, monthUsage],
            models: models,
            modelsWindowLabel: "All models this week",
            inputTokens: totals.input,
            outputTokens: totals.output,
            cacheReadTokens: totals.cacheRead,
            cacheWriteTokens: totals.cacheWrite,
            totalSessions: Set(planEvents.map(\.sessionID)).filter { !$0.isEmpty }.count,
            isEstimated: true,
            monthlyTokens: monthTotals.input + monthTotals.output + monthTotals.cacheRead + monthTotals.cacheWrite,
            monthlyEstimatedUSD: monthEstimated
        )
    }

    static func fetchWeekHeatmap(now: Date = Date()) throws -> OpenCodeWeekHeatmap {
        try fetchWeekHeatmap(dbURL: databaseURL, now: now)
    }

    static func fetchWeekHeatmap(dbURL: URL, now: Date = Date()) throws -> OpenCodeWeekHeatmap {
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw OpenCodeLocalStatsError.databaseMissing(dbURL)
        }
        let week = weeklyBounds(now: now)
        let rows = try readAssistantMessageRows(
            from: dbURL,
            startMS: Int64(week.start.timeIntervalSince1970 * 1000),
            endMS: Int64(week.end.timeIntervalSince1970 * 1000)
        )
        return buildWeekHeatmap(rows: rows, now: now)
    }

    static func fetchDayHourlyUsage(now: Date = Date()) throws -> OpenCodeDayHourlyUsage {
        try fetchDayHourlyUsage(dbURL: databaseURL, now: now)
    }

    static func fetchDayHourlyUsage(dbURL: URL, now: Date = Date()) throws -> OpenCodeDayHourlyUsage {
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw OpenCodeLocalStatsError.databaseMissing(dbURL)
        }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        // Per-message model/cost — session.model only stores one model and misses switches (e.g. ChatGPT).
        let rows = try readAssistantMessageRows(
            from: dbURL,
            startMS: Int64(dayStart.timeIntervalSince1970 * 1000),
            endMS: Int64(dayEnd.timeIntervalSince1970 * 1000)
        )
        return buildDayHourlyUsage(rows: rows, now: now)
    }

    /// Local-calendar day, 24 hourly stacks of model cost (all providers).
    static func buildDayHourlyUsage(
        rows: [SessionRow],
        now: Date = Date(),
        maxLegendModels: Int = 8
    ) -> OpenCodeDayHourlyUsage {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let dayRows = rows.filter { inWindow($0, start: dayStart, end: dayEnd) }

        // hour → modelKey → (provider, model, cost, messages)
        var byHour: [Int: [String: (providerID: String, modelID: String, cost: Double, messages: Int)]] = [:]
        var modelTotals: [String: (providerID: String, modelID: String, cost: Double)] = [:]
        var hourMessageCounts: [Int: Int] = [:]

        for row in dayRows {
            let time = Date(timeIntervalSince1970: TimeInterval(row.timeCreatedMS) / 1000)
            let hour = calendar.component(.hour, from: time)
            let key = "\(row.providerID)/\(row.modelID)"
            var hourMap = byHour[hour] ?? [:]
            var entry = hourMap[key] ?? (row.providerID, row.modelID, 0, 0)
            entry.cost += row.costUSD
            entry.messages += 1
            hourMap[key] = entry
            byHour[hour] = hourMap
            hourMessageCounts[hour, default: 0] += 1

            var total = modelTotals[key] ?? (row.providerID, row.modelID, 0)
            total.cost += row.costUSD
            modelTotals[key] = total
        }

        let hours: [OpenCodeHourUsage] = (0..<24).map { hour in
            let segs = (byHour[hour] ?? [:]).values
                .filter { $0.cost > 0 || $0.messages > 0 }
                .sorted { lhs, rhs in
                    if lhs.cost != rhs.cost { return lhs.cost > rhs.cost }
                    return lhs.messages > rhs.messages
                }
                .map {
                    OpenCodeHourSegment(
                        providerID: $0.providerID,
                        modelID: $0.modelID,
                        costUSD: $0.cost,
                        messageCount: $0.messages
                    )
                }
            return OpenCodeHourUsage(
                hour: hour,
                segments: segs,
                messageCount: hourMessageCounts[hour] ?? 0
            )
        }

        let legend = modelTotals.values
            .sorted { $0.cost > $1.cost }
            .prefix(maxLegendModels)
            .map {
                OpenCodeHourLegendItem(
                    id: "\($0.providerID)/\($0.modelID)",
                    label: $0.modelID,
                    providerID: $0.providerID,
                    modelID: $0.modelID
                )
            }

        return OpenCodeDayHourlyUsage(dayStart: dayStart, hours: hours, legend: Array(legend))
    }

    static func buildWeekHeatmap(rows: [SessionRow], now: Date = Date(), maxRows: Int = 6) -> OpenCodeWeekHeatmap {
        let week = weeklyBounds(now: now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let dayStarts: [Date] = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: week.start)
        }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dayFormatter.dateFormat = "EEEEE"
        let dayLabels = dayStarts.map { dayFormatter.string(from: $0) }

        let weekRows = rows
            .filter { inWindow($0, start: week.start, end: week.end) }
            .filter { planEligibleProvider($0.providerID) }

        // Aggregate cost (or sessions) per model per day index.
        var byModel: [String: (providerID: String, modelID: String, days: [Double], sessions: [Double])] = [:]
        for row in weekRows {
            let key = "\(row.providerID)/\(row.modelID)"
            var entry = byModel[key] ?? (row.providerID, row.modelID, Array(repeating: 0, count: 7), Array(repeating: 0, count: 7))
            let time = Date(timeIntervalSince1970: TimeInterval(row.timeCreatedMS) / 1000)
            let dayStart = calendar.startOfDay(for: time)
            guard let dayIndex = dayStarts.firstIndex(of: dayStart) else { continue }
            entry.days[dayIndex] += OpenCodeZenCostEstimate.billableCostUSD(
                providerID: row.providerID,
                modelID: row.modelID,
                recordedCostUSD: row.costUSD,
                inputTokens: row.inputTokens,
                outputTokens: row.outputTokens,
                cacheReadTokens: row.cacheReadTokens,
                cacheWriteTokens: row.cacheWriteTokens
            ).cost
            entry.sessions[dayIndex] += 1
            byModel[key] = entry
        }

        let useSessions = byModel.values.allSatisfy { $0.days.allSatisfy { $0 <= 0 } }
        var heatmapRows: [OpenCodeHeatmapRow] = byModel.values.compactMap { entry in
            let values = useSessions ? entry.sessions : entry.days
            let hasUsage = values.contains { $0 > 0 }
            guard hasUsage else { return nil }
            return OpenCodeHeatmapRow(
                providerID: entry.providerID,
                modelID: entry.modelID,
                dayValues: values
            )
        }
        heatmapRows.sort { $0.weekTotal > $1.weekTotal }
        if heatmapRows.count > maxRows {
            heatmapRows = Array(heatmapRows.prefix(maxRows))
        }

        return OpenCodeWeekHeatmap(
            weekStart: week.start,
            dayLabels: dayLabels,
            rows: heatmapRows
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
        var sessionsByKey: [String: Set<String>] = [:]
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
                percentOfWindow: 0,
                isCostEstimated: false
            )
            if row.sessionID.isEmpty {
                usage.sessionCount += 1
            } else {
                var ids = sessionsByKey[key] ?? []
                ids.insert(row.sessionID)
                sessionsByKey[key] = ids
                usage.sessionCount = ids.count
            }
            usage.inputTokens += row.inputTokens
            usage.outputTokens += row.outputTokens
            usage.cacheReadTokens += row.cacheReadTokens
            usage.cacheWriteTokens += row.cacheWriteTokens

            let billable = OpenCodeZenCostEstimate.billableCostUSD(
                providerID: row.providerID,
                modelID: row.modelID,
                recordedCostUSD: row.costUSD,
                inputTokens: row.inputTokens,
                outputTokens: row.outputTokens,
                cacheReadTokens: row.cacheReadTokens,
                cacheWriteTokens: row.cacheWriteTokens
            )
            usage.costUSD += billable.cost
            if billable.isEstimated {
                usage.isCostEstimated = true
            }
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

    private static func estimatedCostUSD(rows: [SessionRow]) -> Double {
        rows.reduce(0) { sum, row in
            sum + OpenCodeZenCostEstimate.billableCostUSD(
                providerID: row.providerID,
                modelID: row.modelID,
                recordedCostUSD: row.costUSD,
                inputTokens: row.inputTokens,
                outputTokens: row.outputTokens,
                cacheReadTokens: row.cacheReadTokens,
                cacheWriteTokens: row.cacheWriteTokens
            ).cost
        }
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

    /// Assistant messages carry the real per-turn model + cost (sessions only store one model).
    private static func readAssistantMessageRows(
        from dbURL: URL,
        startMS: Int64,
        endMS: Int64
    ) throws -> [SessionRow] {
        var db: OpaquePointer?
        let uri = "file:\(dbURL.path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            throw OpenCodeLocalStatsError.openFailed(message)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)

        let sql = """
        SELECT time_created, session_id, data \
        FROM message \
        WHERE time_created >= ? AND time_created < ? \
          AND json_extract(data, '$.role') = 'assistant'
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw OpenCodeLocalStatsError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, startMS)
        sqlite3_bind_int64(stmt, 2, endMS)

        var rows: [SessionRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let dataText = sqlite3_column_text(stmt, 2),
                  let data = String(cString: dataText).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let providerID = (json["providerID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelID = (json["modelID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let providerID, !providerID.isEmpty, let modelID, !modelID.isEmpty else { continue }

            let tokens = json["tokens"] as? [String: Any]
            let cache = tokens?["cache"] as? [String: Any]
            let sessionID = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""

            rows.append(SessionRow(
                timeCreatedMS: sqlite3_column_int64(stmt, 0),
                costUSD: (json["cost"] as? Double) ?? (json["cost"] as? NSNumber)?.doubleValue ?? 0,
                inputTokens: int64Value(tokens?["input"]),
                outputTokens: int64Value(tokens?["output"]),
                cacheReadTokens: int64Value(cache?["read"]),
                cacheWriteTokens: int64Value(cache?["write"]),
                providerID: providerID,
                modelID: modelID,
                sessionID: sessionID
            ))
        }
        return rows
    }

    private static func int64Value(_ value: Any?) -> Int64 {
        if let n = value as? Int64 { return n }
        if let n = value as? Int { return Int64(n) }
        if let n = value as? Double { return Int64(n) }
        if let n = value as? NSNumber { return n.int64Value }
        return 0
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
