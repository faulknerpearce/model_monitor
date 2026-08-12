@testable import ModelMonitor
import XCTest

final class FormatTests: XCTestCase {
    // MARK: tokens

    func testTokensBelowThousandShowsBareCount() {
        XCTAssertEqual(Format.tokens(0), "0")
        XCTAssertEqual(Format.tokens(999), "999")
    }

    func testTokensThousands() {
        XCTAssertEqual(Format.tokens(1_000), "1K")
        XCTAssertEqual(Format.tokens(12_400), "12K")
    }

    func testTokensMillionsRoundsToOneDecimalBelowTen() {
        XCTAssertEqual(Format.tokens(1_000_000), "1.0M")
        XCTAssertEqual(Format.tokens(1_234_567), "1.2M")
    }

    func testTokensMillionsRoundsWholeAtTenPlus() {
        XCTAssertEqual(Format.tokens(10_000_000), "10M")
        XCTAssertEqual(Format.tokens(123_000_000), "123M")
    }

    func testTokensBillions() {
        XCTAssertEqual(Format.tokens(1_000_000_000), "1.0B")
        XCTAssertEqual(Format.tokens(2_500_000_000), "2.5B")
    }

    // MARK: usd

    func testUSDFormatsCurrencyWithoutTilde() {
        XCTAssertEqual(Format.usd(4.1), "$4.10")
        XCTAssertEqual(Format.usd(0), "$0.00")
    }

    // MARK: hourLabel

    func testHourLabelTwelveHourClock() {
        XCTAssertEqual(Format.hourLabel(for: 0), "12a")
        XCTAssertEqual(Format.hourLabel(for: 12), "12p")
        XCTAssertEqual(Format.hourLabel(for: 5), "5a")
        XCTAssertEqual(Format.hourLabel(for: 11), "11a")
        XCTAssertEqual(Format.hourLabel(for: 13), "1p")
        XCTAssertEqual(Format.hourLabel(for: 15), "3p")
        XCTAssertEqual(Format.hourLabel(for: 23), "11p")
    }

    // MARK: parseFlexible

    func testParseFlexiblePlainAndFractional() throws {
        let plain = try XCTUnwrap(ISO8601DateFormatter.parseFlexible("2026-07-16T20:25:00Z"))
        XCTAssertEqual(plain.timeIntervalSince1970, 1_784_233_500, accuracy: 1)

        let fractional = try XCTUnwrap(ISO8601DateFormatter.parseFlexible("2026-07-16T20:25:00.123Z"))
        XCTAssertEqual(fractional.timeIntervalSince1970, 1_784_233_500.123, accuracy: 0.001)
    }

    func testParseFlexibleRejectsGarbage() {
        XCTAssertNil(ISO8601DateFormatter.parseFlexible("not a date"))
    }

    // MARK: resetDate

    func testResetDateMatchesNaiveFormatterAndLowercasesMeridian() throws {
        let utc = TimeZone(secondsFromGMT: 0)
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-16T18:57:00Z"))

        let naive = DateFormatter()
        naive.locale = Locale(identifier: "en_US_POSIX")
        naive.timeZone = utc
        naive.dateFormat = "EEE h:mma"
        let expected = naive.string(from: date)
            .replacingOccurrences(of: "AM", with: "am")
            .replacingOccurrences(of: "PM", with: "pm")

        XCTAssertEqual(Format.resetDate(date, dateFormat: "EEE h:mma", timeZone: utc), expected)
        XCTAssertTrue(expected.hasSuffix("pm"))
    }
}
