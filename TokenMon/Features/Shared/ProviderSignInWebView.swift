import SwiftUI
import WebKit

/// Shared WebKit sign-in host: starts at the provider's auth URL, notifies
/// when an auth host is seen, and fires exactly once when the return page loads.
struct ProviderSignInWebView: NSViewRepresentable {
    var startURL: URL
    /// Isolated store for this provider's sign-in (cookies never leak across providers).
    var dataStore: WKWebsiteDataStore
    var isAuthHost: (String, String) -> Bool
    var isReturnPage: (URL) -> Bool
    var onAuthHostSeen: () -> Void
    var onReturned: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            startURL: startURL,
            isAuthHost: isAuthHost,
            isReturnPage: isReturnPage,
            onAuthHostSeen: onAuthHostSeen,
            onReturned: onReturned
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: startURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onAuthHostSeen = onAuthHostSeen
        context.coordinator.onReturned = onReturned
        context.coordinator.isAuthHost = isAuthHost
        context.coordinator.isReturnPage = isReturnPage
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var isAuthHost: (String, String) -> Bool
        var isReturnPage: (URL) -> Bool
        var onAuthHostSeen: () -> Void
        var onReturned: (URL) -> Void
        private var didSeeAuth = false
        private var didReturn = false

        init(
            startURL: URL,
            isAuthHost: @escaping (String, String) -> Bool,
            isReturnPage: @escaping (URL) -> Bool,
            onAuthHostSeen: @escaping () -> Void,
            onReturned: @escaping (URL) -> Void
        ) {
            self.isAuthHost = isAuthHost
            self.isReturnPage = isReturnPage
            self.onAuthHostSeen = onAuthHostSeen
            self.onReturned = onReturned
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url { handle(url: url) }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url { handle(url: url) }
            decisionHandler(.allow)
        }

        // Allow OAuth popups / new windows inside the same web view.
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
            if !didSeeAuth, isAuthHost(host, url.path) {
                didSeeAuth = true
                onAuthHostSeen()
            }
            if didSeeAuth, !didReturn, isReturnPage(url) {
                didReturn = true
                onReturned(url)
            }
        }
    }
}
