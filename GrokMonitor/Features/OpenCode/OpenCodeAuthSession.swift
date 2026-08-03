import Foundation
import Combine
import os
import WebKit

/// Console session for opencode.ai (OpenAuth cookie `auth`).
/// Separate from Grok WebKit cookies so the two providers do not clobber each other.
@MainActor
final class OpenCodeAuthSession: ObservableObject {
    private let logger = Logger(subsystem: "com.grokmonitor.app", category: "OpenCodeAuth")

    @Published private(set) var isSignedIn = false
    @Published private(set) var accountEmail: String?
    @Published var needsSignIn = true
    @Published private(set) var lastAuthError: String?
    /// Last known workspace id (`wrk_…`) from redirect or prior fetch.
    @Published private(set) var workspaceID: String?

    private let store = FileBackedStringStore(filenamePrefix: "opencode_auth_")

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
        // Keep workspace id as a hint for the next successful login.
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
    /// Retries briefly — SolidStart sets the encrypted `auth` cookie slightly after navigation.
    func captureCookiesFromWebKit() async -> Bool {
        for attempt in 1...4 {
            let cookies = await WKWebsiteDataStoreBridge.shared.allCookies()
            let relevant = cookies.filter { Self.isOpenCodeDomain($0.domain) }
            // Console session is the SolidStart `auth` cookie (Fe26.2**…); `provider` is JWT-ish.
            let sessionCookie = relevant.first { $0.name == "auth" || $0.name.lowercased() == "auth" }
            let authCookies = relevant.filter { Self.looksLikeAuthCookie($0) }

            logger.info(
                "OpenCode cookie capture attempt \(attempt, privacy: .public): relevant=\(relevant.count, privacy: .public) authNamed=\(sessionCookie != nil, privacy: .public) authish=\(authCookies.count, privacy: .public)"
            )

            if sessionCookie != nil || !authCookies.isEmpty {
                // Prefer all opencode-domain cookies (auth + provider).
                let chosen = relevant.isEmpty ? authCookies : relevant
                let header = chosen.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                writeStore(key: "session", value: header)

                if let email = Self.extractEmail(from: chosen) {
                    writeStore(key: "email", value: email)
                    accountEmail = email
                }

                for cookie in chosen {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }

                isSignedIn = true
                needsSignIn = false
                lastAuthError = nil
                logger.info("Captured OpenCode console cookies (\(chosen.count, privacy: .public))")
                return true
            }

            if attempt < 4 {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }

        lastAuthError = "No OpenCode console session cookie found. Finish signing in until you see your workspace, then click Capture Session."
        return false
    }

    func signOut() {
        removeStore(key: "session")
        removeStore(key: "email")
        removeStore(key: "workspace")
        let storage = HTTPCookieStorage.shared
        for domain in ["opencode.ai", "auth.opencode.ai"] {
            if let url = URL(string: "https://\(domain)") {
                storage.cookies(for: url)?.forEach { storage.deleteCookie($0) }
            }
        }
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

    // MARK: - Domain / cookie helpers

    nonisolated static func isOpenCodeDomain(_ domain: String) -> Bool {
        Domain.matches(domain, hosts: ["opencode.ai", "auth.opencode.ai"])
    }

    private static func looksLikeAuthCookie(_ cookie: HTTPCookie) -> Bool {
        let name = cookie.name.lowercased()
        if name == "auth" || name == "session" || name == "sid" { return true }
        let hints = ["auth", "session", "token", "jwt", "sid", "account", "openid", "oauth"]
        return hints.contains { name.contains($0) }
    }

    private static func extractEmail(from cookies: [HTTPCookie]) -> String? {
        for cookie in cookies {
            let value = cookie.value
            if value.contains("@"), value.count < 200, !value.contains(" ") {
                return value
            }
        }
        return nil
    }

    // MARK: - Disk

    private func writeStore(key: String, value: String) {
        store.set(value, forKey: key)
    }

    private func readStore(key: String) -> String? {
        store.value(forKey: key)
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
