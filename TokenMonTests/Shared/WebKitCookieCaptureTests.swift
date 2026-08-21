@testable import TokenMon
import XCTest

/// Pure email extraction from captured cookies.
final class WebKitCookieCaptureTests: XCTestCase {
    private func cookie(name: String, value: String) -> HTTPCookie {
        HTTPCookie(properties: [
            .domain: "example.com",
            .path: "/",
            .name: name,
            .value: value
        ])!
    }

    func testExtractsEmailNamedCookie() {
        let cookies = [cookie(name: "email", value: "dev%40example.com")]
        XCTAssertEqual(WebKitCookieCapture.extractEmail(from: cookies), "dev@example.com")
    }

    func testExtractsUserEmailNamedCookie() {
        let cookies = [cookie(name: "user_email", value: "someone@example.org")]
        XCTAssertEqual(WebKitCookieCapture.extractEmail(from: cookies), "someone@example.org")
    }

    func testFallsBackToShortValueContainingAt() {
        let cookies = [cookie(name: "track", value: "fallback@example.io")]
        XCTAssertEqual(WebKitCookieCapture.extractEmail(from: cookies), "fallback@example.io")
    }

    func testIgnoresLongValuesWithSpaces() {
        let cookies = [cookie(name: "session", value: "a b c d e f g h i j k l m n o p q r s t u v w x y z @ long token value here padding padding")]
        XCTAssertNil(WebKitCookieCapture.extractEmail(from: cookies))
    }

    func testReturnsNilWithoutEmailLikeCookies() {
        let cookies = [cookie(name: "theme", value: "dark")]
        XCTAssertNil(WebKitCookieCapture.extractEmail(from: cookies))
    }

    func testPrefersExplicitEmailCookieOverFallback() {
        let cookies = [
            cookie(name: "track", value: "fallback@example.com"),
            cookie(name: "email", value: "primary@example.com")
        ]
        XCTAssertEqual(WebKitCookieCapture.extractEmail(from: cookies), "primary@example.com")
    }
}
