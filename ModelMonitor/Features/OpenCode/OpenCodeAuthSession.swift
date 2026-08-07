import Combine
import Foundation
import os
import WebKit

/// Console session for opencode.ai (OpenAuth cookie `auth`).
/// Separate from Grok WebKit cookies so the two providers do not clobber each other.
@MainActor
final class OpenCodeAuthSession: ObservableObject, ProviderCookieCapturing {
    private let logger = Logger(subsystem: "com.modelmonitor.app", category: "OpenCodeAuth")

    @Published private(set) var isSignedIn = false
    @Published private(set) var accountEmail: String?
    @Published var needsSignIn = true
    @Published private(set) var lastAuthError: String?
    /// Last known workspace id (`wrk_…`) from redirect or prior fetch.
    @Published private(set) var workspaceID: String?

    private let store = FileBackedStringStore(filenamePrefix: "opencode_auth_")

    private static let capturePolicy = WebKitCookieCapture.Policy(
        isDomain: isOpenCodeDomain,
        isPreferredSessionCookie: { $0.name.lowercased() == "auth" },
        looksLikeAuthCookie: { cookie in
            let name = cookie.name.lowercased()
            if name == "auth" || name == "session" || name == "sid" { return true }
            let hints = ["auth", "session", "token", "jwt", "sid", "account", "openid", "oauth"]
            return hints.contains { name.contains($0) }
        },
        includeAllDomainCookiesWhenSessionFound: true,
        maxAttempts: 4,
        failureMessage: "No OpenCode console session cookie found. Finish signing in until you see your workspace, then click Capture Session."
    )

    init() {
        refreshFromDisk()
    }

    func refreshFromDisk() {
        let cookies = loadCookieHeader()
        isSignedIn = !(cookies?.isEmpty ?? true)
        needsSignIn = !isSignedIn
        accountEmail = loadEmail()
        workspaceID = loadWorkspaceID()
    }

    func markSessionInvalid(reason: String? = nil) {
        needsSignIn = true
        if let reason { lastAuthError = reason }
        removeStore(key: "session")
        removeStore(key: "email")
        isSignedIn = false
        logger.info("OpenCode console session marked invalid")
    }

    func cookieHeader() -> String? {
        loadCookieHeader()
    }

    func saveWorkspaceID(_ id: String) {
        writeStore(key: "workspace", value: id)
        workspaceID = id
    }

    /// Captures opencode.ai / auth.opencode.ai cookies from the default WebKit store.
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
        logger.info("Captured OpenCode console cookies (\(result.cookies.count, privacy: .public))")
        return true
    }

    func signOut() {
        removeStore(key: "session")
        removeStore(key: "email")
        removeStore(key: "workspace")
        WebKitCookieCapture.clearHTTPCookieStorage(hosts: ["opencode.ai", "auth.opencode.ai"])
        Task {
            await WKWebsiteDataStoreBridge.shared.clearCookies(matching: Self.isOpenCodeDomain)
        }
        isSignedIn = false
        needsSignIn = true
        accountEmail = nil
        workspaceID = nil
        lastAuthError = nil
        logger.info("OpenCode signed out")
    }

    nonisolated static func isOpenCodeDomain(_ domain: String) -> Bool {
        Domain.matches(domain, hosts: ["opencode.ai", "auth.opencode.ai"])
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

    private func loadWorkspaceID() -> String? {
        store.value(forKey: "workspace")
    }
}
