import SwiftUI

struct ChatGPTSignInView: View {
    @ObservedObject var auth: ChatGPTAuthSession
    var onComplete: () -> Void

    var body: some View {
        ProviderSignInSheet(
            auth: auth,
            config: ProviderSignInConfig(
                title: "Sign in to ChatGPT",
                initialStatus: "Sign in to your ChatGPT account. When you reach chatgpt.com, click Capture Session.",
                authHostStatus: "Complete sign-in. When you land back on chatgpt.com, click Capture Session.",
                capturingStatus: "Back on ChatGPT — capturing session…",
                startURL: URL(string: "https://chatgpt.com/")!,
                isAuthHost: { host, path in
                    host.contains("auth.openai")
                        || host.contains("auth0.openai")
                        || host.contains("accounts.google")
                        || host.contains("appleid.apple")
                        || host.contains("login.microsoft")
                        || path.contains("/login")
                        || path.contains("/signin")
                },
                isReturnPage: { url in
                    guard let host = url.host?.lowercased() else { return false }
                    let onChatGPT = host == "chatgpt.com" || host.hasSuffix(".chatgpt.com")
                    return onChatGPT && url.path == "/" || (onChatGPT && !url.path.contains("login"))
                }
            ),
            onComplete: onComplete
        )
    }
}
