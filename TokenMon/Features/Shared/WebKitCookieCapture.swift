import Foundation
import WebKit

/// Shared WebKit cookie capture with provider-specific domain/session policy.
enum WebKitCookieCapture {
    struct Policy: Sendable {
        var isDomain: @Sendable (String) -> Bool
        /// Preferred session cookie (e.g. `auth`, `WorkosCursorSessionToken`).
        var isPreferredSessionCookie: @Sendable (HTTPCookie) -> Bool
        var looksLikeAuthCookie: @Sendable (HTTPCookie) -> Bool
        /// When preferred session is found, include all domain cookies if non-empty.
        var includeAllDomainCookiesWhenSessionFound: Bool
        var maxAttempts: Int
        var retryDelayNanoseconds: UInt64
        var failureMessage: String

        init(
            isDomain: @escaping @Sendable (String) -> Bool,
            isPreferredSessionCookie: @escaping @Sendable (HTTPCookie) -> Bool = { _ in false },
            looksLikeAuthCookie: @escaping @Sendable (HTTPCookie) -> Bool,
            includeAllDomainCookiesWhenSessionFound: Bool = true,
            maxAttempts: Int = 1,
            retryDelayNanoseconds: UInt64 = 400_000_000,
            failureMessage: String
        ) {
            self.isDomain = isDomain
            self.isPreferredSessionCookie = isPreferredSessionCookie
            self.looksLikeAuthCookie = looksLikeAuthCookie
            self.includeAllDomainCookiesWhenSessionFound = includeAllDomainCookiesWhenSessionFound
            self.maxAttempts = maxAttempts
            self.retryDelayNanoseconds = retryDelayNanoseconds
            self.failureMessage = failureMessage
        }
    }

    struct CaptureResult: Sendable {
        var cookies: [HTTPCookie]
        var cookieHeader: String
        var email: String?
    }

    @MainActor
    static func capture(policy: Policy) async -> CaptureResult? {
        let attempts = max(1, policy.maxAttempts)
        for attempt in 1...attempts {
            let cookies = await WKWebsiteDataStoreBridge.shared.allCookies()
            let relevant = cookies.filter { policy.isDomain($0.domain) }
            let preferred = relevant.first(where: policy.isPreferredSessionCookie)
            let authish = relevant.filter { policy.looksLikeAuthCookie($0) }

            let chosen: [HTTPCookie]?
            if preferred != nil {
                if policy.includeAllDomainCookiesWhenSessionFound, !relevant.isEmpty {
                    chosen = relevant
                } else if let preferred {
                    chosen = [preferred]
                } else {
                    chosen = nil
                }
            } else if !authish.isEmpty {
                chosen = policy.includeAllDomainCookiesWhenSessionFound && !relevant.isEmpty
                    ? relevant
                    : authish
            } else {
                chosen = nil
            }

            if let chosen, !chosen.isEmpty {
                let header = chosen.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                return CaptureResult(
                    cookies: chosen,
                    cookieHeader: header,
                    email: extractEmail(from: chosen)
                )
            }

            if attempt < attempts {
                try? await Task.sleep(nanoseconds: policy.retryDelayNanoseconds)
            }
        }
        return nil
    }

    static func extractEmail(from cookies: [HTTPCookie]) -> String? {
        for cookie in cookies {
            let name = cookie.name.lowercased()
            if ["email", "user_email"].contains(name) {
                let decoded = cookie.value.removingPercentEncoding ?? cookie.value
                if decoded.contains("@"), decoded.contains(".") {
                    return decoded
                }
            }
        }
        for cookie in cookies {
            let value = cookie.value
            if value.contains("@"), value.count < 200, !value.contains(" ") {
                return value
            }
        }
        return nil
    }

    @MainActor
    static func clearHTTPCookieStorage(hosts: [String]) {
        let storage = HTTPCookieStorage.shared
        for domain in hosts {
            if let url = URL(string: "https://\(domain)") {
                storage.cookies(for: url)?.forEach { storage.deleteCookie($0) }
            }
        }
    }
}
