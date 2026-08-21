@testable import TokenMon
import XCTest

/// DailyBudget math: per-day allowance, period windows, over-budget flags.
final class DailyBudgetTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar = gregorian
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testBudgetPerDayDividesEvenly() {
        XCTAssertEqual(DailyBudget.budgetPerDay(limitUSD: 100, daysInPeriod: 7), 100.0 / 7, accuracy: 1e-9)
    }

    func testBudgetPerDayZeroGuards() {
        XCTAssertEqual(DailyBudget.budgetPerDay(limitUSD: 0, daysInPeriod: 7), 0)
        XCTAssertEqual(DailyBudget.budgetPerDay(limitUSD: 100, daysInPeriod: 0), 0)
    }

    func testDaysInBillingCycleCountsInclusiveStartExclusiveEnd() {
        let start = date(2026, 8, 1)
        let end = date(2026, 8, 8)
        XCTAssertEqual(DailyBudget.daysInBillingCycle(start: start, end: end, calendar: calendar), 7)
    }

    func testDaysInBillingCycleMinimumOne() {
        let same = date(2026, 8, 1)
        XCTAssertEqual(DailyBudget.daysInBillingCycle(start: same, end: same, calendar: calendar), 1)
    }

    func testBuildDaysCoversWholePeriodWithPerDayBudget() {
        // Contract: spentByDay is keyed by calendar.startOfDay.
        let spent: [Date: Double] = [calendar.startOfDay(for: date(2026, 8, 1)): 10]
        let days = DailyBudget.buildDays(
            periodStart: date(2026, 8, 1),
            periodEnd: date(2026, 8, 8),
            limitUSD: 70,
            spentByDay: spent,
            calendar: calendar
        )
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days[0].spentUSD, 10)
        XCTAssertEqual(days[1].spentUSD, 0)
        for day in days {
            XCTAssertEqual(day.budgetUSD, 10, accuracy: 1e-9)
        }
    }

    func testOverBudgetFlag() {
        let over = DailyBudgetDay(date: date(2026, 8, 1), spentUSD: 15, budgetUSD: 10)
        let under = DailyBudgetDay(date: date(2026, 8, 2), spentUSD: 5, budgetUSD: 10)
        XCTAssertTrue(over.isOverBudget)
        XCTAssertFalse(under.isOverBudget)
        // percentOfBudget clamps at 100 even when over budget.
        XCTAssertEqual(over.percentOfBudget, 100)
    }

    func testPercentOfBudgetZeroBudgetIsZero() {
        let day = DailyBudgetDay(date: date(2026, 8, 1), spentUSD: 15, budgetUSD: 0)
        XCTAssertEqual(day.percentOfBudget, 0)
        XCTAssertFalse(day.isOverBudget)
    }

    func testLast7AtPeriodStartPadsForward() {
        // Period starts today: only one real day exists; window must still be 7 bars.
        let today = date(2026, 8, 1)
        let days = DailyBudget.buildLast7Days(
            periodStart: today,
            periodEnd: date(2026, 9, 1),
            limitUSD: 310,
            spentByDay: [:],
            now: today,
            calendar: calendar
        )
        XCTAssertEqual(days.count, 7)
    }

    func testBuildCalendarMonthDaysMatchesMonthLength() {
        let days = DailyBudget.buildCalendarMonthDays(
            containing: date(2026, 2, 15),
            limitUSD: 280,
            spentByDay: [:],
            calendar: calendar
        )
        XCTAssertEqual(days.count, 28, "2026 is not a leap year")
    }

    func testBuildRolling7DaysEndsToday() {
        let now = date(2026, 8, 20)
        let days = DailyBudget.buildRolling7Days(
            limitUSD: 70,
            daysInPeriod: 30,
            spentByDay: [:],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(calendar.isDate(days.last?.date ?? Date(), inSameDayAs: now), true)
        XCTAssertEqual(calendar.isDate(days.first?.date ?? Date(), inSameDayAs: date(2026, 8, 14)), true)
    }
}
