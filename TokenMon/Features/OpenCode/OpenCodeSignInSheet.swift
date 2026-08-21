import SwiftUI

struct OpenCodeSignInView: View {
    @ObservedObject var auth: OpenCodeAuthSession
    var onComplete: () -> Void

    var body: some View {
        ProviderSignInSheet(
            auth: auth,
            config: ProviderSignInConfig(
                title: "Sign in to OpenCode",
                initialStatus: "Sign in to your OpenCode account. When you reach the console/workspace, click Capture Session.",
                authHostStatus: "Complete sign-in. When you land on the OpenCode console, click Capture Session.",
                capturingStatus: "Back on OpenCode — capturing session…",
                startURL: URL(string: "https://opencode.ai/auth/authorize")!,
                isAuthHost: { host, path in
                    host.contains("auth.opencode.ai") || path.contains("/auth/authorize")
                },
                isReturnPage: { url in
                    guard let host = url.host?.lowercased() else { return false }
                    let onConsoleDomain = host == "opencode.ai" || host.hasSuffix(".opencode.ai")
                    return onConsoleDomain
                        && !host.contains("auth.")
                        && (url.path.contains("/workspace")
                                || (url.path.hasPrefix("/auth") && !url.path.contains("authorize")))
                },
                onReturned: { url in
                    if let id = OpenCodeConsoleClient.workspaceID(from: url) {
                        auth.saveWorkspaceID(id)
                    }
                }
            ),
            onComplete: onComplete,
            afterCapture: {
                if let cookie = auth.cookieHeader() {
                    let client = OpenCodeConsoleClient(cookieHeader: cookie)
                    if let id = try? await client.resolveWorkspaceID() {
                        auth.saveWorkspaceID(id)
                    }
                }
            }
        )
    }
}
