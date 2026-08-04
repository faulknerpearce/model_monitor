import Foundation
import Combine
import SwiftData
import SQLite3
import os

@Model
final class UsageSnapshotRecord {
    @Attribute(.unique) var id: UUID
    var fetchedAt: Date
    var usedPercent: Double
    var remainingPercent: Double
    var resetsAt: Date?
    var productsJSON: Data
    /// Stored as Double for SwiftData schema stability; domain model uses Decimal.
    var extraCredits: Double?
    var accountEmail: String?

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    private static let logger = Logger(subsystem: "com.modelmonitor.app", category: "History")

    init(from snapshot: WeeklyUsageSnapshot) {
        self.id = snapshot.id
        self.fetchedAt = snapshot.fetchedAt
        self.usedPercent = snapshot.usedPercent
        self.remainingPercent = snapshot.remainingPercent
        self.resetsAt = snapshot.resetsAt
        if let data = try? Self.encoder.encode(snapshot.products) {
            self.productsJSON = data
        } else {
            Self.logger.error("Failed to encode products for snapshot \(snapshot.id)")
            self.productsJSON = Data()
        }
        self.extraCredits = snapshot.extraCreditsBalance.map { NSDecimalNumber(decimal: $0).doubleValue }
        self.accountEmail = snapshot.accountEmail
    }

    func apply(_ snapshot: WeeklyUsageSnapshot) {
        fetchedAt = snapshot.fetchedAt
        usedPercent = snapshot.usedPercent
        remainingPercent = snapshot.remainingPercent
        resetsAt = snapshot.resetsAt
        if let data = try? Self.encoder.encode(snapshot.products) {
            productsJSON = data
        } else {
            Self.logger.error("Failed to encode products on apply for \(snapshot.id)")
        }
        extraCredits = snapshot.extraCreditsBalance.map { NSDecimalNumber(decimal: $0).doubleValue }
        accountEmail = snapshot.accountEmail
    }

    func toSnapshot() -> WeeklyUsageSnapshot {
        let products: [ProductUsage]
        if let decoded = try? Self.decoder.decode([ProductUsage].self, from: productsJSON) {
            products = decoded
        } else {
            Self.logger.error("Failed to decode productsJSON for record \(self.id)")
            products = []
        }
        return WeeklyUsageSnapshot(
            id: id,
            fetchedAt: fetchedAt,
            usedPercent: usedPercent,
            remainingPercent: remainingPercent,
            resetsAt: resetsAt,
            products: products,
            extraCreditsBalance: extraCredits.map { Decimal($0) },
            accountEmail: accountEmail
        )
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    private static let logger = Logger(subsystem: "com.modelmonitor.app", category: "HistoryStore")

    private var container: ModelContainer?
    private var context: ModelContext?

    @Published private(set) var recent: [WeeklyUsageSnapshot] = []

    init(inMemory: Bool = false) {
        do {
            let config: ModelConfiguration
            if inMemory {
                config = ModelConfiguration(isStoredInMemoryOnly: true)
            } else {
                let storeURL = Self.persistentStoreURL()
                config = ModelConfiguration(url: storeURL)
            }
            let container = try ModelContainer(for: UsageSnapshotRecord.self, configurations: config)
            self.container = container
            self.context = ModelContext(container)
            reload()
        } catch {
            Self.logger.error("SwiftData init failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stable Application Support store so history survives renames / sandbox toggles.
    private static func persistentStoreURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("ModelMonitor", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let storeURL = dir.appendingPathComponent("history.store")
        migrateLegacyStoreIfNeeded(to: storeURL, applicationSupportBase: base)
        return storeURL
    }

    /// Import richer history from older app IDs or the App Sandbox container.
    ///
    /// Leaving the sandbox changes Application Support from
    /// `~/Library/Containers/com.grokmonitor.app/.../GrokMonitor/` to
    /// `~/Library/Application Support/ModelMonitor/`. Without this migration the
    /// daily bars lose multi-day samples and look empty.
    ///
    /// Picks the candidate with the **most snapshot rows** (not first match / not
    /// WAL byte size). A thin non-sandbox store can still have a huge WAL from
    /// recent writes while missing the multi-day series in the container.
    private static func migrateLegacyStoreIfNeeded(to storeURL: URL, applicationSupportBase base: URL) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let flagKey = "didMigrateModelMonitorHistoryFromSandboxV2"

        let legacyCandidates: [URL] = [
            // Sandboxed Grok Monitor (legacy source after disabling App Sandbox)
            home.appendingPathComponent(
                "Library/Containers/com.grokmonitor.app/Data/Library/Application Support/GrokMonitor/history.store"
            ),
            home.appendingPathComponent(
                "Library/Containers/com.grokmonitor.app/Data/Library/Application Support/GrokMonitor/default.store"
            ),
            base.appendingPathComponent("GrokMonitor/history.store"),
            base.appendingPathComponent("GrokMonitor/default.store"),
            home.appendingPathComponent(
                "Library/Containers/com.modelmonitor.app/Data/Library/Application Support/ModelMonitor/history.store"
            ),
            home.appendingPathComponent(
                "Library/Containers/com.modelmonitor.app/Data/Library/Application Support/ModelMonitor/default.store"
            ),
            // Pre-rename GrokUsage
            home.appendingPathComponent(
                "Library/Containers/com.grokusage.app/Data/Library/Application Support/default.store"
            ),
            home.appendingPathComponent(
                "Library/Containers/com.grokusage.app/Data/Library/Application Support/GrokUsage/history.store"
            ),
            home.appendingPathComponent(
                "Library/Containers/com.grokusage.app/Data/Library/Application Support/GrokUsage/default.store"
            ),
            base.appendingPathComponent("default.store"),
            base.appendingPathComponent("GrokUsage/history.store"),
            base.appendingPathComponent("GrokUsage/default.store")
        ]

        let destStandard = storeURL.standardizedFileURL
        let candidates = legacyCandidates.filter { url in
            let standard = url.standardizedFileURL
            guard standard != destStandard else { return false }
            return fm.fileExists(atPath: url.path)
        }
        guard !candidates.isEmpty else {
            if !UserDefaults.standard.bool(forKey: flagKey) {
                UserDefaults.standard.set(true, forKey: flagKey)
            }
            return
        }

        guard let legacy = candidates.max(by: { storeHistoryScore($0) < storeHistoryScore($1) }) else {
            return
        }

        let legacyScore = storeHistoryScore(legacy)
        let currentExists = fm.fileExists(atPath: storeURL.path)
        let currentScore = currentExists
            ? storeHistoryScore(storeURL)
            : HistoryStoreScore(rowCount: 0, mainBytes: 0)

        // Replace when legacy has more snapshot rows (or equal rows but a larger main DB).
        let shouldReplace = !currentExists || legacyScore > currentScore
        guard shouldReplace else {
            if !UserDefaults.standard.bool(forKey: flagKey) {
                UserDefaults.standard.set(true, forKey: flagKey)
            }
            return
        }

        do {
            // Keep a one-shot backup of the thinner store before overwriting.
            if currentExists, currentScore.rowCount > 0 || currentScore.mainBytes > 0 {
                let backup = storeURL.deletingLastPathComponent()
                    .appendingPathComponent("history.pre-sandbox-migrate.store")
                try? fm.removeItem(at: backup)
                try? fm.copyItem(at: storeURL, to: backup)
                for suffix in ["-shm", "-wal"] {
                    let side = URL(fileURLWithPath: storeURL.path + suffix)
                    let dest = URL(fileURLWithPath: backup.path + suffix)
                    try? fm.removeItem(at: dest)
                    if fm.fileExists(atPath: side.path) {
                        try? fm.copyItem(at: side, to: dest)
                    }
                }
            }

            if currentExists {
                try fm.removeItem(at: storeURL)
            }
            for suffix in ["-shm", "-wal"] {
                let side = URL(fileURLWithPath: storeURL.path + suffix)
                if fm.fileExists(atPath: side.path) {
                    try? fm.removeItem(at: side)
                }
            }
            try fm.copyItem(at: legacy, to: storeURL)
            for suffix in ["-shm", "-wal"] {
                let side = URL(fileURLWithPath: legacy.path + suffix)
                let dest = URL(fileURLWithPath: storeURL.path + suffix)
                if fm.fileExists(atPath: side.path) {
                    try? fm.copyItem(at: side, to: dest)
                }
            }
            UserDefaults.standard.set(true, forKey: flagKey)
            logger.info(
                "Migrated history store (\(legacyScore.rowCount) rows) from \(legacy.path, privacy: .public)"
            )
        } catch {
            logger.error("History migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private struct HistoryStoreScore: Comparable {
        var rowCount: Int
        var mainBytes: Int

        static func < (lhs: HistoryStoreScore, rhs: HistoryStoreScore) -> Bool {
            if lhs.rowCount != rhs.rowCount { return lhs.rowCount < rhs.rowCount }
            return lhs.mainBytes < rhs.mainBytes
        }
    }

    /// Prefer more `UsageSnapshotRecord` rows; fall back to main-file size (ignore WAL bloat).
    private static func storeHistoryScore(_ storeURL: URL) -> HistoryStoreScore {
        let fm = FileManager.default
        let mainBytes = (try? fm.attributesOfItem(atPath: storeURL.path)[.size] as? NSNumber)?.intValue ?? 0
        let rows = sqliteSnapshotRowCount(storeURL) ?? 0
        return HistoryStoreScore(rowCount: rows, mainBytes: mainBytes)
    }

    private static func sqliteSnapshotRowCount(_ storeURL: URL) -> Int? {
        var db: OpaquePointer?
        let uri = "file:\(storeURL.path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1000)

        // SwiftData entity table name for UsageSnapshotRecord
        let sql = "SELECT COUNT(*) FROM ZUSAGESNAPSHOTRECORD"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    func append(_ snapshot: WeeklyUsageSnapshot) {
        guard let context else { return }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: snapshot.fetchedAt)

        if let last = recent.first,
           cal.isDate(last.fetchedAt, inSameDayAs: snapshot.fetchedAt),
           abs(last.usedPercent - snapshot.usedPercent) < 0.05,
           abs(last.fetchedAt.timeIntervalSince(snapshot.fetchedAt)) < 60
        {
            return
        }

        let sameDay = findRecords(on: dayStart, calendar: cal)
        if let existing = sameDay.first {
            existing.apply(snapshot)
            // Collapse legacy duplicates so each calendar day has one end-of-day row.
            if sameDay.count > 1 {
                for extra in sameDay.dropFirst() {
                    context.delete(extra)
                }
            }
            save(context: context)
            upsertRecent(snapshot, replacingID: existing.id)
            return
        }

        let record = UsageSnapshotRecord(from: snapshot)
        context.insert(record)
        save(context: context)
        upsertRecent(snapshot)
    }

    /// Keep `recent` in sync without re-fetching (and re-decoding) up to 200 rows.
    private func upsertRecent(_ snapshot: WeeklyUsageSnapshot, replacingID: UUID? = nil) {
        if let replacingID, let index = recent.firstIndex(where: { $0.id == replacingID }) {
            recent[index] = snapshot
            return
        }
        recent.insert(snapshot, at: 0)
        if recent.count > 200 {
            recent.removeLast(recent.count - 200)
        }
    }

    func allSnapshots() -> [WeeklyUsageSnapshot] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<UsageSnapshotRecord>(
            sortBy: [SortDescriptor(\.fetchedAt, order: .forward)]
        )
        let records = (try? context.fetch(descriptor)) ?? []
        return records.map { $0.toSnapshot() }
    }

    func clear() {
        guard let context else { return }
        do {
            let records = try context.fetch(FetchDescriptor<UsageSnapshotRecord>())
            for record in records {
                context.delete(record)
            }
            try context.save()
            recent = []
        } catch {
            Self.logger.error("Clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Same-day lookup: fetch a window, then filter with `Calendar` (more reliable than exact predicate bounds).
    private func findRecords(on dayStart: Date, calendar: Calendar) -> [UsageSnapshotRecord] {
        guard let context else { return [] }
        let windowStart = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
        let windowEnd = calendar.date(byAdding: .day, value: 2, to: dayStart) ?? dayStart
        let descriptor = FetchDescriptor<UsageSnapshotRecord>(
            predicate: #Predicate { record in
                record.fetchedAt >= windowStart && record.fetchedAt < windowEnd
            },
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )
        let candidates = (try? context.fetch(descriptor)) ?? []
        return candidates.filter { calendar.isDate($0.fetchedAt, inSameDayAs: dayStart) }
    }

    private func reload() {
        guard let context else { return }
        var descriptor = FetchDescriptor<UsageSnapshotRecord>(
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        let records = (try? context.fetch(descriptor)) ?? []
        recent = records.map { $0.toSnapshot() }
    }

    private func save(context: ModelContext) {
        do {
            try context.save()
        } catch {
            Self.logger.error("SwiftData save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
