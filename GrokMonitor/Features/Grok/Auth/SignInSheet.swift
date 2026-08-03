import SwiftUI
import AppKit

struct SignInView: View {
    @ObservedObject var auth: AuthSessionService
    var onComplete: () -> Void

    @State private var statusMessage =
        "Sign in with your Grok / xAI account below. When you land back on grok.com, click Capture Session."
    @State private var isCapturing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to Grok")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
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

            ProviderSignInWebView(
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
                onAuthHostSeen: {
                    statusMessage = "Complete sign-in in the page. When you return to grok.com, click Capture Session."
                },
                onReturned: { _ in
                    // Cookies commit slightly after the redirect lands.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        statusMessage = "Back on grok.com — capturing session…"
                        Task { await capture() }
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
            statusMessage = "Session captured."
            onComplete()
            dismiss()
        } else {
            statusMessage = auth.lastAuthError
                ?? "No session cookies found yet. Finish signing in, then click Capture Session."
        }
    }
}
