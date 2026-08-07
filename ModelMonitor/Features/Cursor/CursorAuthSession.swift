import Combine
import Foundation
import os
import WebKit

/// Session for cursor.com (`WorkosCursorSessionToken`).
/// Separate cookie store from Grok / OpenCode so providers do not clobber each other.
@MainActor
final class CursorAuthSession: ObservableObject, ProviderCookieCapturing {
    private let logger = Logger(subsystem: "com.modelmonitor.app", category: "CursorAuth")

    @Published private(set) var isSignedIn = false
    @Published private(set) var accountEmail: String?
    @Published var needsSignIn = true
    @Published private(set) var lastAuthError: String?

    private let store = FileBackedStringStore(filenamePrefix: "cursor_auth_")

    private static let capturePolicy = WebKitCookieCapture.Policy(
        isDomain: isCursorDomain,
        isPreferredSessionCookie: {
            $0.name == "WorkosCursorSessionToken"
                || $0.name.lowercased() == "workoscursorsessiontoken"
        },
        looksLikeAuthCookie: { cookie in
            let name = cookie.name.lowercased()
            if name == "workoscursorsessiontoken" { return true }
            let hints = ["session", "token", "auth", "workos", "cursor"]
            return hints.contains { name.contains($0) }
        },
        includeAllDomainCookiesWhenSessionFound: true,
        maxAttempts: 4,
        failureMessage: "No Cursor session cookie found. Finish signing in until you see the usage dashboard, then click Capture Session."
    )

    init() {
        refreshFromDisk()
    }

    func refreshFromDisk() {
        let cookies = loadCookieHeader()
        isSignedIn = !(cookies?.isEmpty ?? true)
        needsSignIn = !isSignedIn
        accountEmail = loadEmail()
    }

    func markSessionInvalid(reason: String? = nil) {
        needsSignIn = true
        if let reason { lastAuthError = reason }
        removeStore(key: "session")
        removeStore(key: "email")
        isSignedIn = false
        logger.info("Cursor session marked invalid")
    }

    func cookieHeader() -> String? {
        loadCookieHeader()
    }

    func saveAccountEmail(_ email: String) {
        writeStore(key: "email", value: email)
        accountEmail = email
    }

    func captureCookiesFromWebKit() async -> Bool {
        guard let result = await WebKitCookieCapture.capture(policy: Self.capturePolicy) else {
            lastAuthError = Self.capturePolicy.failureMessage
            return false
        }

        writeStore(key: "session", value: result.cookieHeader)
        if let email = result.email {
            writeStore(key: "email", value: email)
            accountEmail = email
        }
        for cookie in result.cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }

        isSignedIn = true
        needsSignIn = false
        lastAuthError = nil
        logger.info("Captured Cursor session cookies (\(result.cookies.count, privacy: .public))")
        return true
    }

    func signOut() {
        removeStore(key: "session")
        removeStore(key: "email")
        WebKitCookieCapture.clearHTTPCookieStorage(hosts: [
            "cursor.com", "www.cursor.com", "authenticator.cursor.sh", "api2.cursor.sh"
        ])
        Task {
            await WKWebsiteDataStoreBridge.shared.clearCookies(matching: Self.isCursorDomain)
        }
        isSignedIn = false
        needsSignIn = true
        accountEmail = nil
        lastAuthError = nil
        logger.info("Cursor signed out")
    }

    nonisolated static func isCursorDomain(_ domain: String) -> Bool {
        Domain.matches(domain, hosts: [
            "cursor.com",
            "cursor.sh",
            "authenticator.cursor.sh",
            "api2.cursor.sh"
        ])
    }

    private func writeStore(key: String, value: String) {
        store.set(value, forKey: key)
    }

    private func removeStore(key: String) {
        store.remove(forKey: key)
    }

    private func loadCookieHeader() -> String? {
        store.value(forKey: "session")
    }

    private func loadEmail() -> String? {
        store.value(forKey: "email")
    }
}
