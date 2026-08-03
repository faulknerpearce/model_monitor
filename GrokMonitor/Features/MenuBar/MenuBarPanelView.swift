import SwiftUI
import AppKit

struct MenuBarPanelView: View {
    @ObservedObject var auth: AuthSessionService
    @ObservedObject var poller: UsagePoller
    @ObservedObject var openCodeAuth: OpenCodeAuthSession
    @ObservedObject var openCodePoller: OpenCodeUsagePoller
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: HistoryStore
    @ObservedObject var grokHourly: GrokHourlyActivityStore

    var openPreferences: () -> Void
    var openCharts: () -> Void
    var openSignIn: () -> Void
    var openOpenCodeSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProviderSwitcherView(selection: $settings.selectedProvider)

            Divider().padding(.vertical, 6)

            switch settings.selectedProvider {
            case .overview:
                overviewContent
            case .opencode:
                openCodeContent
            case .grok:
                grokContent
            }

            Divider().padding(.vertical, 6)

            menuActions
        }
        .padding(12)
        .frame(width: settings.selectedProvider == .overview ? 420 : 340)
        .animation(.easeInOut(duration: 0.15), value: settings.selectedProvider)
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
        // Menu bar always shows Grok, so always refresh it.
        async let grok: Void = poller.refreshNow()
        if settings.selectedProvider.pollsOpenCode {
            async let openCode: Void = openCodePoller.refreshNow()
            _ = await (grok, openCode)
        } else {
            await grok
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

    private var overviewContent: some View {
        OverviewPanelView(
            grokPoller: poller,
            openCodePoller: openCodePoller,
            grokHourly: grokHourly,
            grokAuth: auth,
            openCodeAuth: openCodeAuth,
            openGrokSignIn: openSignIn,
            openOpenCodeSignIn: openOpenCodeSignIn
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
                .font(PanelTypography.body)
            }

            Toggle(isOn: $settings.showBarGraphInMenuBar) {
                toggleLabel("Show Bar Graph in Menu Bar", isOn: settings.showBarGraphInMenuBar)
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .font(PanelTypography.body)

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
                        .font(PanelTypography.body)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .font(PanelTypography.body)
    }

    private func toggleLabel(_ title: String, isOn: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if isOn {
                Image(systemName: "checkmark")
                    .font(PanelTypography.bodySemibold)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }
}
