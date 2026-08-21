import WebKit

/// Provider-neutral access to a WebKit cookie store.
/// Each provider session owns an isolated non-persistent store so cookies
/// never leak between providers (e.g. X/Twitter sessions into the Grok jar).
@MainActor
enum WKWebsiteDataStoreBridge {
    static let shared = WKWebsiteDataStoreBridgeImpl()
}

@MainActor
final class WKWebsiteDataStoreBridgeImpl {
    func allCookies(in store: WKWebsiteDataStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    func clearCookies(matching predicate: (String) -> Bool, in store: WKWebsiteDataStore) async {
        let cookies = await allCookies(in: store)
        for cookie in cookies where predicate(cookie.domain) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.httpCookieStore.delete(cookie) {
                    continuation.resume()
                }
            }
        }
    }

    /// Removes every cookie from the given store (used for per-provider isolation).
    func clearAllCookies(in store: WKWebsiteDataStore) async {
        let cookies = await allCookies(in: store)
        for cookie in cookies {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.httpCookieStore.delete(cookie) {
                    continuation.resume()
                }
            }
        }
    }
}
