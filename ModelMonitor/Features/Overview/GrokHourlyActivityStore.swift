import Foundation
import Combine

/// Tracks today’s Grok weekly-pool growth per local hour (percent-point deltas between polls).
@MainActor
final class GrokHourlyActivityStore: ObservableObject {
    @Published private(set) var hourWeights: [Double]
    @Published private(set) var dayStart: Date

    private let store: FileBackedStringStore
    private let legacyStore: FileBackedStringStore?
    private let key = "grok_hourly_today"
    private var lastUsedPercent: Double?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private struct Payload: Codable {
        var dayStart: Date
        var hourWeights: [Double]
        var lastUsedPercent: Double?
    }

    convenience init() {
        self.init(
            store: FileBackedStringStore(filenamePrefix: "activity_"),
            legacyStore: FileBackedStringStore(
            subdirectory: "GrokMonitor",
            filenamePrefix: "activity_"
            )
        )
    }

    convenience init(store: FileBackedStringStore) {
        self.init(store: store, legacyStore: nil)
    }

    init(store: FileBackedStringStore, legacyStore: FileBackedStringStore?) {
        self.store = store
        self.legacyStore = legacyStore
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        self.dayStart = today
        self.hourWeights = Array(repeating: 0, count: 24)
        loadOrReset(for: today)
    }

    /// Record a new Grok snapshot. Only positive growth since the last sample counts.
    func record(usedPercent: Double, at date: Date = Date()) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        if start != dayStart {
            dayStart = start
            hourWeights = Array(repeating: 0, count: 24)
            lastUsedPercent = nil
        }

        defer {
            lastUsedPercent = usedPercent
            persist()
        }

        guard let previous = lastUsedPercent else { return }

        let delta = usedPercent - previous
        // Ignore tiny noise and week-reset drops.
        guard delta >= 0.05 else { return }

        let hour = calendar.component(.hour, from: date)
        guard (0..<24).contains(hour) else { return }
        var next = hourWeights
        next[hour] += delta
        hourWeights = next
    }

    private func loadOrReset(for today: Date) {
        let raw = migrateLegacyValueIfNeeded() ?? store.value(forKey: key)
        guard let raw,
              let data = raw.data(using: .utf8),
              let payload = try? decoder.decode(Payload.self, from: data)
        else {
            persist()
            return
        }

        if Calendar.current.isDate(payload.dayStart, inSameDayAs: today),
           payload.hourWeights.count == 24 {
            dayStart = Calendar.current.startOfDay(for: payload.dayStart)
            hourWeights = payload.hourWeights
            lastUsedPercent = payload.lastUsedPercent
        } else {
            dayStart = today
            hourWeights = Array(repeating: 0, count: 24)
            lastUsedPercent = nil
            persist()
        }
    }

    private func migrateLegacyValueIfNeeded() -> String? {
        guard let legacyStore,
              let legacyRaw = legacyStore.value(forKey: key),
              let legacyData = legacyRaw.data(using: .utf8),
              let legacyPayload = try? decoder.decode(Payload.self, from: legacyData)
        else { return nil }

        if let currentRaw = store.value(forKey: key),
           let currentData = currentRaw.data(using: .utf8),
           let currentPayload = try? decoder.decode(Payload.self, from: currentData),
           !currentPayload.hourWeights.allSatisfy({ $0 == 0 }) {
            return nil
        }

        guard !legacyPayload.hourWeights.allSatisfy({ $0 == 0 }) || legacyPayload.lastUsedPercent != nil else {
            return nil
        }

        store.set(legacyRaw, forKey: key)
        return legacyRaw
    }

    private func persist() {
        let payload = Payload(
            dayStart: dayStart,
            hourWeights: hourWeights,
            lastUsedPercent: lastUsedPercent
        )
        guard let data = try? encoder.encode(payload),
              let raw = String(data: data, encoding: .utf8)
        else { return }
        store.set(raw, forKey: key)
    }
}
