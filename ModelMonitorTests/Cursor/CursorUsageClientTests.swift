import XCTest
@testable import ModelMonitor

final class CursorUsageClientTests: XCTestCase {
    func testParseSummaryUsesTotalAutoAPIPercents() throws {
        let json = """
        {
          "billingCycleStart": "2026-07-13T00:00:00.000Z",
          "billingCycleEnd": "2026-08-14T12:00:00.000Z",
          "membershipType": "ultra",
          "individualUsage": {
            "plan": {
              "enabled": true,
              "used": 7600,
              "limit": 40000,
              "remaining": 32400,
              "totalPercentUsed": 19,
              "autoPercentUsed": 16,
              "apiPercentUsed": 30
            },
            "onDemand": {
              "enabled": true,
              "used": 2309,
              "limit": null,
              "remaining": null
            }
          }
        }
        """.data(using: .utf8)!

        let now = ISO8601DateFormatter().date(from: "2026-08-03T18:00:00Z")!
        let snap = try CursorUsageClient.parseSummary(data: json, fetchedAt: now)
        XCTAssertEqual(snap.usedPercent, 19, accuracy: 0.01)
        XCTAssertEqual(snap.pools.count, 3)
        XCTAssertEqual(snap.pools[0].kind, .total)
        XCTAssertEqual(snap.pools[0].remainingPercent, 81, accuracy: 0.01)
        XCTAssertEqual(snap.pools[1].kind, .auto)
        XCTAssertEqual(snap.pools[1].remainingPercent, 84, accuracy: 0.01)
        XCTAssertEqual(snap.pools[2].kind, .api)
        XCTAssertEqual(snap.pools[2].remainingPercent, 70, accuracy: 0.01)
        XCTAssertEqual(snap.planUsedUSD ?? -1, 76, accuracy: 0.01)
        XCTAssertEqual(snap.planLimitUSD ?? -1, 400, accuracy: 0.01)
        XCTAssertEqual(snap.membershipType, "ultra")
        XCTAssertEqual(snap.displayPlanName, "Cursor Ultra")
        XCTAssertNotNil(snap.pools[0].pace)
        XCTAssertTrue(snap.pools[0].pace?.isReserve == true)
    }

    func testParseSummaryAveragesAutoAndAPIWhenTotalMissing() throws {
        let json = """
        {
          "individualUsage": {
            "plan": {
              "enabled": true,
              "used": 0,
              "limit": 0,
              "autoPercentUsed": 10,
              "apiPercentUsed": 30
            },
            "onDemand": { "enabled": false }
          }
        }
        """.data(using: .utf8)!

        let snap = try CursorUsageClient.parseSummary(data: json)
        XCTAssertEqual(snap.usedPercent, 20, accuracy: 0.01)
        XCTAssertEqual(snap.pools.count, 3)
    }

    func testParseSummaryFallsBackToUsedOverLimitCents() throws {
        let json = """
        {
          "individualUsage": {
            "plan": {
              "enabled": true,
              "used": 2500,
              "limit": 10000
            },
            "onDemand": { "enabled": false }
          }
        }
        """.data(using: .utf8)!

        let snap = try CursorUsageClient.parseSummary(data: json)
        XCTAssertEqual(snap.usedPercent, 25, accuracy: 0.01)
        XCTAssertEqual(snap.planUsedUSD ?? -1, 25, accuracy: 0.01)
        XCTAssertEqual(snap.planLimitUSD ?? -1, 100, accuracy: 0.01)
        XCTAssertEqual(snap.pools.count, 1)
    }

    func testPaceReserveMath() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 100)
        // 50% elapsed → expected 50% used. Actual 20% → 30% reserve.
        let now = Date(timeIntervalSince1970: 50)
        let pace = CursorPace.compute(usedPercent: 20, cycleStart: start, cycleEnd: end, now: now)
        XCTAssertEqual(pace?.expectedUsedPercent ?? -1, 50, accuracy: 0.01)
        XCTAssertEqual(pace?.deltaPercent ?? -1, 30, accuracy: 0.01)
        XCTAssertEqual(pace?.paceLabel, "30% in reserve")
        XCTAssertTrue(pace?.willLastUntilReset == true)
    }

    func testAggregateCostStats() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 3
        components.hour = 12
        let now = calendar.date(from: components)!
        let dayStart = calendar.startOfDay(for: now)
        let cycleStart = calendar.date(byAdding: .day, value: -20, to: dayStart)!

        let events: [[String: Any]] = [
            [
                "timestamp": String(Int64(now.timeIntervalSince1970 * 1000)),
                "chargedCents": 1202,
                "tokenUsage": ["inputTokens": 1_000_000, "outputTokens": 500_000, "cacheWriteTokens": 0, "cacheReadTokens": 0]
            ],
            [
                "timestamp": String(Int64(dayStart.addingTimeInterval(-2 * 86400).timeIntervalSince1970 * 1000)),
                "chargedCents": 5000,
                "tokenUsage": ["inputTokens": 2_000_000, "outputTokens": 0, "cacheWriteTokens": 0, "cacheReadTokens": 0]
            ]
        ]

        let stats = CursorUsageClient.aggregateCostStats(
            events: events,
            cycleStart: cycleStart,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(stats.todayUSD, 12.02, accuracy: 0.01)
        XCTAssertEqual(stats.meteredCycleUSD, 62.02, accuracy: 0.01)
        XCTAssertEqual(stats.cycleTokens, 3_500_000)
        XCTAssertEqual(stats.last20dUSD, 62.02, accuracy: 0.01)
        XCTAssertEqual(stats.todayTokens, 1_500_000)
        XCTAssertEqual(stats.last20dTokens, 3_500_000)
    }

    func testMostUsedModelRanksByTokenCount() {
        let events: [[String: Any]] = [
            [
                "model": "claude-sonnet-4",
                "tokenUsage": ["inputTokens": 100, "outputTokens": 100]
            ],
            [
                "modelName": "gpt-5",
                "tokenUsage": ["inputTokens": 500, "outputTokens": 500]
            ]
        ]

        XCTAssertEqual(CursorUsageClient.mostUsedModel(from: events), "gpt-5")
    }

    func testHourWeightsBucketByRequestsCosts() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 3
        components.hour = 0
        components.minute = 0
        let dayStart = calendar.date(from: components)!

        let events: [[String: Any]] = [
            [
                "timestamp": String(Int64(dayStart.addingTimeInterval(10 * 3600).timeIntervalSince1970 * 1000)),
                "requestsCosts": 2.5
            ],
            [
                "timestamp": String(Int64(dayStart.addingTimeInterval(10 * 3600 + 60).timeIntervalSince1970 * 1000)),
                "requestsCosts": 1.5
            ],
            [
                "timestamp": String(Int64(dayStart.addingTimeInterval(14 * 3600).timeIntervalSince1970 * 1000)),
                "tokenUsage": [
                    "inputTokens": 100,
                    "outputTokens": 50,
                    "cacheWriteTokens": 0,
                    "cacheReadTokens": 0
                ]
            ]
        ]

        let weights = CursorUsageClient.hourWeights(fromEvents: events, dayStart: dayStart, calendar: calendar)
        XCTAssertEqual(weights.count, 24)
        XCTAssertEqual(weights[10], 4.0, accuracy: 0.01)
        XCTAssertEqual(weights[14], 150, accuracy: 0.01)
        XCTAssertEqual(weights[9], 0, accuracy: 0.01)
    }

    func testQuotaHourWeightsUseChargedCentsAndPlanLimit() {
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_754_236_800))
        let events: [[String: Any]] = [
            [
                "timestamp": String(Int64(dayStart.addingTimeInterval(10 * 3600).timeIntervalSince1970 * 1000)),
                "chargedCents": 100
            ],
            [
                "timestamp": String(Int64(dayStart.addingTimeInterval(10 * 3600 + 60).timeIntervalSince1970 * 1000)),
                "chargedCents": 300
            ]
        ]

        let weights = CursorUsageClient.quotaHourWeights(
            fromEvents: events,
            dayStart: dayStart,
            planLimitUSD: 400,
            calendar: calendar
        )

        XCTAssertEqual(weights[10], 1, accuracy: 0.001)
        XCTAssertEqual(weights[9], 0, accuracy: 0.001)
    }

    func testParseUsageEventsPage() throws {
        let json = """
        {
          "totalUsageEventsCount": 2,
          "usageEventsDisplay": [
            { "timestamp": "1775418973898", "requestsCosts": 1 },
            { "timestamp": "1775418973899", "requestsCosts": 2 }
          ]
        }
        """.data(using: .utf8)!

        let (events, total) = try CursorUsageClient.parseUsageEventsPage(data: json)
        XCTAssertEqual(total, 2)
        XCTAssertEqual(events.count, 2)
    }

    func testCursorDomainFilter() {
        XCTAssertTrue(CursorAuthSession.isCursorDomain("cursor.com"))
        XCTAssertTrue(CursorAuthSession.isCursorDomain(".cursor.com"))
        XCTAssertTrue(CursorAuthSession.isCursorDomain("www.cursor.com"))
        XCTAssertTrue(CursorAuthSession.isCursorDomain("authenticator.cursor.sh"))
        XCTAssertFalse(CursorAuthSession.isCursorDomain("opencode.ai"))
        XCTAssertFalse(CursorAuthSession.isCursorDomain("grok.com"))
    }
}
