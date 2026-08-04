import SwiftUI

struct CursorSignInView: View {
    @ObservedObject var auth: CursorAuthSession
    var onComplete: () -> Void

    var body: some View {
        ProviderSignInSheet(
            auth: auth,
            config: ProviderSignInConfig(
                title: "Sign in to Cursor",
                initialStatus: "Sign in to your Cursor account. When you reach the usage dashboard, click Capture Session.",
                authHostStatus: "Complete sign-in. When you land on the Cursor dashboard, click Capture Session.",
                capturingStatus: "Back on Cursor — capturing session…",
                startURL: URL(string: "https://cursor.com/dashboard/usage")!,
                isAuthHost: { host, path in
                    host.contains("authenticator.cursor")
                        || host.contains("accounts.google")
                        || host.contains("github.com")
                        || path.contains("/login")
                        || path.contains("/signin")
                },
                isReturnPage: { url in
                    guard let host = url.host?.lowercased() else { return false }
                    let onCursor = host == "cursor.com" || host.hasSuffix(".cursor.com")
                    return onCursor
                        && (url.path.contains("/dashboard") || url.path.contains("/settings"))
                }
            ),
            onComplete: onComplete
        )
    }
}
