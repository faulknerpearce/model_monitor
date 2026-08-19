import SwiftUI

struct SignInView: View {
    @ObservedObject var auth: AuthSessionService
    var onComplete: () -> Void

    var body: some View {
        ProviderSignInSheet(
            auth: auth,
            config: ProviderSignInConfig(
                title: "Sign in to Grok",
                initialStatus: "Sign in with your Grok / xAI account below. When you land back on grok.com, click Capture Session.",
                authHostStatus: "Complete sign-in in the page. When you return to grok.com, click Capture Session.",
                capturingStatus: "Back on grok.com — capturing session…",
                startURL: URL(
                    string: "https://accounts.x.ai/sign-in?redirect=https%3A%2F%2Fgrok.com%2F%3F_s%3Dusage"
                )!,
                isAuthHost: { host, _ in
                    ["accounts.x.ai", "auth.x.ai", "api.x.com", "twitter.com", "x.com"]
                        .contains { host.contains($0) }
                },
                isReturnPage: { url in
                    url.host?.lowercased().contains("grok.com") ?? false
                },
                returnDelayNanoseconds: 1_500_000_000
            ),
            onComplete: onComplete
        )
    }
}
