import SwiftUI
import WebKit
import AppKit

struct OpenCodeSignInView: View {
    @ObservedObject var auth: OpenCodeAuthSession
    var onComplete: () -> Void

    @State private var statusMessage =
        "Sign in to your OpenCode account. When you reach the console/workspace, click Capture Session."
    @State private var isCapturing = false
    @State private var sawAuthHost = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to OpenCode")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Text(statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            if let err = auth.lastAuthError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            OpenCodeSignInWebView(
                onAuthHostSeen: {
                    sawAuthHost = true
                    statusMessage = "Complete sign-in. When you land on the OpenCode console, click Capture Session."
                },
                onReturnedToConsole: { url in
                    if let id = OpenCodeConsoleClient.workspaceID(from: url) {
                        auth.saveWorkspaceID(id)
                    }
                    guard sawAuthHost else { return }
                    // Cookies are often committed just after navigation finishes — wait briefly.
                    statusMessage = "Back on OpenCode — capturing session…"
                    Task {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        await capture()
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                Button("I'm signed in — Capture Session") {
                    Task { await capture() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isCapturing)

                Spacer()

                Button("Done") {
                    onComplete()
                    dismiss()
                }
            }
            .padding()
        }
        .frame(minWidth: 880, minHeight: 640)
        .onAppear {
            NSApp.activate()
        }
    }

    private func capture() async {
        isCapturing = true
        defer { isCapturing = false }
        let ok = await auth.captureCookiesFromWebKit()
        if ok {
            // Best-effort workspace discovery after capture.
            if let cookie = auth.cookieHeader() {
                let client = OpenCodeConsoleClient(cookieHeader: cookie)
                if let id = try? await client.resolveWorkspaceID() {
                    auth.saveWorkspaceID(id)
                }
            }
            statusMessage = "Session captured."
            onComplete()
            dismiss()
        } else {
            statusMessage = auth.lastAuthError
                ?? "No session cookies found yet. Finish signing in, then click Capture Session."
        }
    }
}

struct OpenCodeSignInWebView: NSViewRepresentable {
    var onAuthHostSeen: () -> Void
    var onReturnedToConsole: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAuthHostSeen: onAuthHostSeen, onReturnedToConsole: onReturnedToConsole)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: URL(string: "https://opencode.ai/auth/authorize")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onAuthHostSeen = onAuthHostSeen
        context.coordinator.onReturnedToConsole = onReturnedToConsole
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var onAuthHostSeen: () -> Void
        var onReturnedToConsole: (URL) -> Void
        private var didSeeAuth = false

        init(onAuthHostSeen: @escaping () -> Void, onReturnedToConsole: @escaping (URL) -> Void) {
            self.onAuthHostSeen = onAuthHostSeen
            self.onReturnedToConsole = onReturnedToConsole
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }
            handle(url: url)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url {
                handle(url: url)
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        private func handle(url: URL) {
            let host = url.host?.lowercased() ?? ""
            if host.contains("auth.opencode.ai") || url.path.contains("/auth/authorize") {
                if !didSeeAuth {
                    didSeeAuth = true
                    onAuthHostSeen()
                }
            }
            if host == "opencode.ai" || host.hasSuffix(".opencode.ai"), !host.contains("auth.") {
                if url.path.contains("/workspace") || url.path.hasPrefix("/auth") && !url.path.contains("authorize") {
                    onReturnedToConsole(url)
                }
            }
        }
    }
}
