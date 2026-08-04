import SwiftUI
import AppKit

/// Auth types that can capture a WebKit session for a provider sign-in sheet.
@MainActor
protocol ProviderCookieCapturing: ObservableObject {
    var lastAuthError: String? { get }
    func captureCookiesFromWebKit() async -> Bool
}

struct ProviderSignInConfig {
    var title: String
    var initialStatus: String
    var authHostStatus: String
    var capturingStatus: String
    var startURL: URL
    var isAuthHost: (String, String) -> Bool
    var isReturnPage: (URL) -> Bool
    var returnDelayNanoseconds: UInt64
    /// Optional side effect when the return page is detected (before delayed capture).
    var onReturned: ((URL) -> Void)?

    init(
        title: String,
        initialStatus: String,
        authHostStatus: String,
        capturingStatus: String,
        startURL: URL,
        isAuthHost: @escaping (String, String) -> Bool,
        isReturnPage: @escaping (URL) -> Bool,
        returnDelayNanoseconds: UInt64 = 800_000_000,
        onReturned: ((URL) -> Void)? = nil
    ) {
        self.title = title
        self.initialStatus = initialStatus
        self.authHostStatus = authHostStatus
        self.capturingStatus = capturingStatus
        self.startURL = startURL
        self.isAuthHost = isAuthHost
        self.isReturnPage = isReturnPage
        self.returnDelayNanoseconds = returnDelayNanoseconds
        self.onReturned = onReturned
    }
}

/// Shared sign-in chrome: title, status, WebKit host, Capture / Done.
struct ProviderSignInSheet<Auth: ProviderCookieCapturing>: View {
    @ObservedObject var auth: Auth
    let config: ProviderSignInConfig
    var onComplete: () -> Void
    /// Runs after a successful cookie capture, before dismiss.
    var afterCapture: (() async -> Void)?

    @State private var statusMessage: String
    @State private var isCapturing = false
    @Environment(\.dismiss) private var dismiss

    init(
        auth: Auth,
        config: ProviderSignInConfig,
        onComplete: @escaping () -> Void,
        afterCapture: (() async -> Void)? = nil
    ) {
        self.auth = auth
        self.config = config
        self.onComplete = onComplete
        self.afterCapture = afterCapture
        _statusMessage = State(initialValue: config.initialStatus)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(config.title)
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
                startURL: config.startURL,
                isAuthHost: config.isAuthHost,
                isReturnPage: config.isReturnPage,
                onAuthHostSeen: {
                    statusMessage = config.authHostStatus
                },
                onReturned: { url in
                    config.onReturned?(url)
                    statusMessage = config.capturingStatus
                    Task {
                        if config.returnDelayNanoseconds > 0 {
                            try? await Task.sleep(nanoseconds: config.returnDelayNanoseconds)
                        }
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
            if let afterCapture {
                await afterCapture()
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
