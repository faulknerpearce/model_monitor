import SwiftUI
import AppKit

struct OpenCodeSignInView: View {
    @ObservedObject var auth: OpenCodeAuthSession
    var onComplete: () -> Void

    @State private var statusMessage =
        "Sign in to your OpenCode account. When you reach the console/workspace, click Capture Session."
    @State private var isCapturing = false
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

            ProviderSignInWebView(
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
                onAuthHostSeen: {
                    statusMessage = "Complete sign-in. When you land on the OpenCode console, click Capture Session."
                },
                onReturned: { url in
                    if let id = OpenCodeConsoleClient.workspaceID(from: url) {
                        auth.saveWorkspaceID(id)
                    }
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
