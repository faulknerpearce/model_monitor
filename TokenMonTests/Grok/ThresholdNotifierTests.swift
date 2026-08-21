@testable import TokenMon
import XCTest

/// Pure decision logic for threshold alerts: fire once per crossing,
/// re-arm after a 5+ point drop below the notified threshold.
final class ThresholdNotifierTests: XCTestCase {
    func testFiresWhenCrossingThreshold() {
        XCTAssertTrue(ThresholdNotifier.shouldNotify(usedPercent: 85, threshold: 80, lastNotifiedThreshold: nil))
    }

    func testDoesNotFireBelowThreshold() {
        XCTAssertFalse(ThresholdNotifier.shouldNotify(usedPercent: 79.9, threshold: 80, lastNotifiedThreshold: nil))
        XCTAssertFalse(ThresholdNotifier.shouldNotify(usedPercent: 80, threshold: 81, lastNotifiedThreshold: nil))
    }

    func testDoesNotRefireAtSameThreshold() {
        // Already notified at 80: staying above 80 must not refire at 80.
        XCTAssertFalse(ThresholdNotifier.shouldNotify(usedPercent: 90, threshold: 80, lastNotifiedThreshold: 80))
        // A raised threshold (90) above the last notified value (80) still fires.
        XCTAssertTrue(ThresholdNotifier.shouldNotify(usedPercent: 95, threshold: 90, lastNotifiedThreshold: 80))
    }

    func testReArmsAfterFivePointDrop() {
        // While a notification at/above the threshold is recorded, stay quiet.
        XCTAssertFalse(ThresholdNotifier.shouldNotify(usedPercent: 78, threshold: 75, lastNotifiedThreshold: 81))
        // evaluate() clears the record once usage drops 5+ points below the
        // notified threshold (81 - 5 = 76; 75 < 76). With state cleared,
        // a fresh crossing fires again.
        XCTAssertTrue(ThresholdNotifier.shouldNotify(usedPercent: 75, threshold: 75, lastNotifiedThreshold: nil))
    }

    func testExactBoundaryCountsAsCrossing() {
        XCTAssertTrue(ThresholdNotifier.shouldNotify(usedPercent: 80, threshold: 80, lastNotifiedThreshold: nil))
    }
}
