import SwiftUI
import AppKit

struct MenuBarPanelView: View {
    @ObservedObject var auth: AuthSessionService
    @ObservedObject var poller: UsagePoller
    @ObservedObject var openCodeAuth: OpenCodeAuthSession
    @ObservedObject var openCodePoller: OpenCodeUsagePoller
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: HistoryStore

    var openPreferences: () -> Void
    var openCharts: () -> Void
    var openSignIn: () -> Void
    var openOpenCodeSignIn: () -> Void

    @State private var showGeminiPopup = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                ProviderSwitcherView(selection: $settings.selectedProvider)

                Divider().padding(.vertical, 6)

                if settings.selectedProvider == .opencode {
                    openCodeContent
                } else {
                    grokContent
                }

                Divider().padding(.vertical, 6)

                menuActions
            }
            .padding(12)
            .opacity(showGeminiPopup ? 0 : 1)
            .allowsHitTesting(!showGeminiPopup)

            if showGeminiPopup {
                geminiPopupContent
                    .padding(12)
                    .transition(.opacity)
            }
        }
        .frame(width: 340)
        .animation(.easeInOut(duration: 0.15), value: showGeminiPopup)
        .onAppear {
            poller.menuIsOpen = true
            openCodePoller.menuIsOpen = true
            Task { await refreshActivePoller() }
        }
        .onDisappear {
            poller.menuIsOpen = false
            openCodePoller.menuIsOpen = false
        }
        .onChange(of: settings.selectedProvider) { _, _ in
            Task { await refreshActivePoller() }
        }
    }

    private func refreshActivePoller() async {
        if settings.selectedProvider == .opencode {
            await openCodePoller.refreshNow()
        } else {
            await poller.refreshNow()
        }
    }

    private var grokContent: some View {
        GrokPanelView(
            auth: auth,
            poller: poller,
            settings: settings,
            history: history,
            openSignIn: openSignIn
        )
    }

    @ViewBuilder
    private var openCodeContent: some View {
        OpenCodePanelView(
            poller: openCodePoller,
            auth: openCodeAuth,
            openSignIn: openOpenCodeSignIn
        )
    }

    private var menuActions: some View {
        VStack(spacing: 2) {
            panelButton("Refresh Now", shortcut: "⌘R") {
                Task { await refreshActivePoller() }
            }
            .keyboardShortcut("r", modifiers: [.command])

            if settings.selectedProvider == .grok {
                Toggle(isOn: $settings.showCategoriesInMenuBar) {
                    toggleLabel("Show Categories in Menu Bar", isOn: settings.showCategoriesInMenuBar)
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .font(.system(size: 13))
            }

            Toggle(isOn: $settings.showBarGraphInMenuBar) {
                toggleLabel("Show Bar Graph in Menu Bar", isOn: settings.showBarGraphInMenuBar)
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .font(.system(size: 13))

            if settings.selectedProvider == .grok, !auth.isSignedIn {
                panelButton("Sign In…", shortcut: nil, action: openSignIn)
            }

            Divider().padding(.vertical, 4)

            panelButton("Open Grok Monitor…", shortcut: "⌘O", action: openPreferences)
                .keyboardShortcut("o", modifiers: [.command])

            if settings.selectedProvider == .grok {
                panelButton("Usage History…", shortcut: nil, action: openCharts)
            }

            Divider().padding(.vertical, 4)

            panelButton("Add Gemini", shortcut: nil) {
                showGeminiPopup = true
            }

            Divider().padding(.vertical, 4)

            panelButton("Quit Grok Monitor", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }

    private func panelButton(_ title: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .font(.system(size: 13))
    }

    private func toggleLabel(_ title: String, isOn: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }

    private var geminiPopupContent: some View {
        ZStack {
            VStack(spacing: 16) {
                Image(nsImage: Self.noGeminiImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text("Use a better model.")
                    .font(.system(size: 16, weight: .semibold))
            }

            VStack {
                HStack {
                    Button {
                        showGeminiPopup = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    Spacer()
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Prefer the bundled PNG file so MenuBarExtra reliably shows the provided artwork.
    private static let noGeminiImage: NSImage = {
        let image: NSImage
        if let url = Bundle.main.url(forResource: "NoGemini", withExtension: "png"),
           let fromFile = NSImage(contentsOf: url) {
            image = fromFile
        } else if let named = NSImage(named: "NoGemini") {
            image = (named.copy() as? NSImage) ?? named
        } else {
            image = NSImage(size: NSSize(width: 140, height: 140))
        }
        image.isTemplate = false
        return image
    }()

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        f.locale = Locale(identifier: "en_US")
        return f
    }()
}
