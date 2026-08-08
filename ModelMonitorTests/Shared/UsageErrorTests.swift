@testable import ModelMonitor
import XCTest

final class UsageErrorTests: XCTestCase {
    func testLocalizedDescriptions() {
        XCTAssertFalse(UsageError.notSignedIn.localizedDescription.isEmpty)
        XCTAssertFalse(UsageError.unauthorized.localizedDescription.isEmpty)
        XCTAssertFalse(UsageError.network("timeout").localizedDescription.isEmpty)
        XCTAssertFalse(UsageError.badResponse("boom").localizedDescription.isEmpty)
    }

    func testEquality() {
        XCTAssertEqual(UsageError.unauthorized, .unauthorized)
        XCTAssertEqual(UsageError.network("x"), .network("x"))
        XCTAssertNotEqual(UsageError.network("x"), .network("y"))
        XCTAssertEqual(UsageError.badResponse("m"), .badResponse("m"))
    }

    func testClientMappingsToCommonAuthCases() {
        XCTAssertEqual(CursorUsageError.unauthorized.usageError, .unauthorized)
        XCTAssertEqual(CursorUsageError.notSignedIn.usageError, .notSignedIn)

        XCTAssertEqual(OpenCodeConsoleError.unauthorized.usageError, .unauthorized)
        XCTAssertEqual(OpenCodeConsoleError.notSignedIn.usageError, .notSignedIn)

        XCTAssertEqual(UsageClientError.unauthorized.usageError, .unauthorized)
        XCTAssertEqual(UsageClientError.notSignedIn.usageError, .notSignedIn)
    }
}
