import Foundation
import Combine
import os
import Security
import WebKit

/// Persists grok.com session cookies and optional bearer token under Application Support.
/// Keychain is intentionally avoided — ad-hoc/debug builds spam "wants to access keychain" dialogs in a loop.
@MainActor
final class AuthSessionService: ObservableObject, ProviderCookieCapturing {
    private let logger = Logger(subsystem: "com.modelmonitor.app", category: "Auth")

    /// Cookie names that indicate a real authenticated session (not anonymous browsing).
    private static let authCookieHints: Set<String> = [
        "sso", "session", "auth", "token", "jwt", "sid", "user", "account",
        "x-session", "xai", "oidc", "refresh", "access"
    ]

    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var accountEmail: String?
    /// True when credentials are missing or the last refresh received 401/403.
    @Published var needsSignIn: Bool = false
    @Published private(set) var lastAuthError: String?

    private let store = FileBackedStringStore(filenamePrefix: "auth_")

    init() {
        // Keychain deletes can stall (SecItemDelete on ad-hoc builds); run off the main actor.
        Task.detached(priority: .utility) {
            KeychainCleanup.deleteLegacyItems()
        }
        Self.migrateLegacyApplicationSupportIfNeeded(current: store.directory)
        refreshFromDisk()
    }

    /// Call when the usage API returns 401/403 so the UI can prompt re-auth.
    func markSessionInvalid(reason: String? = nil) {
        needsSignIn = true
        if let reason {
            lastAuthError = reason
        }
        removeStore(key: "session")
        removeStore(key: "token")
        removeStore(key: "email")
        logger.info("Session marked invalid, on-disk auth cleared")
    }

    func refreshFromDisk() {
        let cookies = loadCookieHeader()
        isSignedIn = !(cookies?.isEmpty ?? true) || loadBearerToken() != nil
        accountEmail = loadAccountEmail()
        needsSignIn = !isSignedIn
    }

    /// Captures authenticated cookies from the shared WKWebsiteDataStore.
    func captureCookiesFromWebKit() async -> Bool {
        let policy = WebKitCookieCapture.Policy(
            isDomain: Self.isGrokDomain,
            looksLikeAuthCookie: { cookie in
                let name = cookie.name.lowercased()
                guard Self.authCookieHints.contains(where: { name.contains($0) }) else { return false }
                return cookie.isSecure || cookie.isHTTPOnly
            },
            includeAllDomainCookiesWhenSessionFound: true,
            maxAttempts: 1,
            failureMessage: "No session cookies found. Finish signing in, then click Capture Session."
        )

        guard let result = await WebKitCookieCapture.capture(policy: policy) else {
            lastAuthError = policy.failureMessage
            logger.warning("No auth cookies found after sign-in")
            return false
        }

        logger.info(
            "Cookie capture: auth cookies=\(result.cookies.count, privacy: .public)"
        )

        save(cookieHeader: result.cookieHeader)
        let storage = HTTPCookieStorage.shared
        for cookie in result.cookies {
            storage.setCookie(cookie)
        }
        if let email = result.email {
            save(accountEmail: email)
        }

        isSignedIn = true
        needsSignIn = false
        lastAuthError = nil
        logger.info("Captured \(result.cookies.count, privacy: .public) session cookies")
        return true
    }

    func save(cookieHeader: String) {
        writeStore(key: "session", value: cookieHeader)
        isSignedIn = true
        needsSignIn = false
    }

    func save(accountEmail: String) {
        writeStore(key: "email", value: accountEmail)
        self.accountEmail = accountEmail
    }

    func save(bearerToken: String) {
        writeStore(key: "token", value: bearerToken)
        isSignedIn = true
        needsSignIn = false
    }

    func loadCookieHeader() -> String? {
        readStore(key: "session")
    }

    func loadBearerToken() -> String? {
        readStore(key: "token")
    }

    func loadAccountEmail() -> String? {
        readStore(key: "email")
    }

    func signOut() {
        removeStore(key: "session")
        removeStore(key: "token")
        removeStore(key: "email")
        WebKitCookieCapture.clearHTTPCookieStorage(hosts: ["grok.com", "x.ai", "x.com"])
        Task {
            await WKWebsiteDataStoreBridge.shared.clearCookies(matching: Self.isGrokDomain)
        }
        isSignedIn = false
        accountEmail = nil
        needsSignIn = true
        lastAuthError = nil
        logger.info("Signed out")
    }

    // MARK: - Helpers

    nonisolated static func isGrokDomain(_ domain: String) -> Bool {
        Domain.matches(domain, hosts: ["grok.com", "x.ai", "x.com", "twitter.com"])
    }

    // MARK: - Application Support store (no Keychain)

    /// Best-effort copy from pre-rename / sandboxed Application Support folders.
    private static func migrateLegacyApplicationSupportIfNeeded(current: URL) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(
                "Library/Containers/com.grokmonitor.app/Data/Library/Application Support/GrokMonitor",
                isDirectory: true
            ),
            base.appendingPathComponent("GrokMonitor", isDirectory: true),
            base.appendingPathComponent("GrokUsage", isDirectory: true),
            home.appendingPathComponent(
                "Library/Containers/com.grokusage.app/Data/Library/Application Support/GrokUsage",
                isDirectory: true
            ),
            home.appendingPathComponent(
                "Library/Containers/com.grokusage.app/Data/Library/Application Support/GrokMonitor",
                isDirectory: true
            )
        ]
        let hasSession = fm.fileExists(atPath: current.appendingPathComponent("auth_session.dat").path)
            || fm.fileExists(atPath: current.appendingPathComponent("auth_token.dat").path)
        guard !hasSession else { return }

        for legacy in candidates {
            let standardLegacy = legacy.standardizedFileURL
            let standardCurrent = current.standardizedFileURL
            guard standardLegacy != standardCurrent else { continue }
            guard fm.fileExists(atPath: legacy.path),
                  let items = try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil),
                  !items.isEmpty
            else { continue }
            try? fm.createDirectory(at: current, withIntermediateDirectories: true)
            for item in items {
                let name = item.lastPathComponent
                guard name.hasPrefix("auth_") else { continue }
                let dest = current.appendingPathComponent(name)
                guard !fm.fileExists(atPath: dest.path) else { continue }
                try? fm.copyItem(at: item, to: dest)
            }
            break
        }
    }

    private func writeStore(key: String, value: String) {
        store.set(value, forKey: key)
    }

    private func readStore(key: String) -> String? {
        store.value(forKey: key)
    }

    private func removeStore(key: String) {
        store.remove(forKey: key)
    }
}

/// Deletes legacy Keychain entries from earlier builds that cause access-dialog loops.
enum KeychainCleanup {
    static func deleteLegacyItems() {
        let services = [
            "com.grokusage.app.cookies",
            "com.grokusage.app.account",
            "com.grokusage.app.bearer",
            "com.grokmonitor.app.cookies",
            "com.grokmonitor.app.account",
            "com.grokmonitor.app.bearer",
            "com.modelmonitor.app.cookies",
            "com.modelmonitor.app.account",
            "com.modelmonitor.app.bearer"
        ]
        let accounts = ["session", "email", "token"]
        for service in services {
            for account in accounts {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account
                ]
                SecItemDelete(query as CFDictionary)
            }
        }
    }
}
