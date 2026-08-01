import WebKit

/// Provider-neutral access to the shared WebKit cookie store.
/// Provider auth services supply their own exact domain predicate.
@MainActor
enum WKWebsiteDataStoreBridge {
    static let shared = WKWebsiteDataStoreBridgeImpl()
}

@MainActor
final class WKWebsiteDataStoreBridgeImpl {
    func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    func clearCookies(matching predicate: (String) -> Bool) async {
        let cookies = await allCookies()
        for cookie in cookies where predicate(cookie.domain) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                WKWebsiteDataStore.default().httpCookieStore.delete(cookie) {
                    continuation.resume()
                }
            }
        }
    }
}
