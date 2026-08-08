@testable import ModelMonitor
import XCTest

final class AuthenticatedRequestTests: XCTestCase {
    private func response(_ status: Int, url: String = "https://example.com/path") -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: url)!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    func testBuildsRequestWithCookieHeader() throws {
        var request = URLRequest(url: URL(string: "https://example.com/path")!)
        request.httpMethod = "POST"
        AuthenticatedRequest.applyHeaders(
            to: &request,
            cookieHeader: "sid=abc",
            bearerToken: nil,
            referer: "https://example.com"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "sid=abc")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://example.com")
    }

    func testAddsBearerTokenWhenPresent() throws {
        var request = URLRequest(url: URL(string: "https://example.com/path")!)
        AuthenticatedRequest.applyHeaders(
            to: &request,
            cookieHeader: nil,
            bearerToken: "tok123",
            referer: nil
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok123")
    }

    func testUnauthorizedStatusMapsToUnauthorized() throws {
        XCTAssertEqual(
            AuthenticatedRequest.mapError(for: self.response(401), data: Data()),
            UsageError.unauthorized
        )
        XCTAssertEqual(
            AuthenticatedRequest.mapError(for: self.response(403), data: Data()),
            UsageError.unauthorized
        )
    }

    func testNon2xxMapsToBadResponse() throws {
        XCTAssertEqual(
            AuthenticatedRequest.mapError(for: self.response(500), data: Data()),
            UsageError.badResponse("HTTP 500 ")
        )
    }

    func testNoErrorOnSuccessRange() {
        XCTAssertNil(AuthenticatedRequest.mapError(for: response(200), data: Data()))
        XCTAssertNil(AuthenticatedRequest.mapError(for: response(204), data: Data()))
    }
}
