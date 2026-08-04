import XCTest
@testable import ModelMonitor

@MainActor
final class GrokHourlyActivityStoreTests: XCTestCase {
    func testMigratesLegacyHourlyWeightsWhenCurrentStoreIsEmpty() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-hourly-migration-\(UUID().uuidString)", isDirectory: true)
        let currentDirectory = root.appendingPathComponent("current", isDirectory: true)
        let legacyDirectory = root.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: currentDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let currentStore = FileBackedStringStore(directory: currentDirectory, filenamePrefix: "activity_")
        let legacyStore = FileBackedStringStore(directory: legacyDirectory, filenamePrefix: "activity_")
        let payload: [String: Any] = [
            "dayStart": Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate,
            "hourWeights": [0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            "lastUsedPercent": 59
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        legacyStore.set(String(decoding: data, as: UTF8.self), forKey: "grok_hourly_today")

        let subject = GrokHourlyActivityStore(store: currentStore, legacyStore: legacyStore)

        XCTAssertEqual(subject.hourWeights[2], 4)
        XCTAssertEqual(subject.hourWeights[11], 6)
        XCTAssertEqual(currentStore.value(forKey: "grok_hourly_today"), legacyStore.value(forKey: "grok_hourly_today"))
    }
}
