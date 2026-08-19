import AppKit
import SwiftUI

struct MenuBarPanelView: View {
    @ObservedObject var auth: AuthSessionService
    @ObservedObject var poller: UsagePoller
    @ObservedObject var openCodeAuth: OpenCodeAuthSession
    @ObservedObject var openCodePoller: OpenCodeUsagePoller
    @ObservedObject var cursorAuth: CursorAuthSession
    @ObservedObject var cursorPoller: CursorUsagePoller
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: HistoryStore
    @ObservedObject var grokHourly: GrokHourlyActivityStore

    let openPreferences: () -> Void
    let openCharts: () -> Void
    let openSignIn: () -> Void
    let openOpenCodeSignIn: () -> Void
    let openCursorSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProviderSwitcherView(selection: $settings.selectedProvider)

            Color.clear.frame(height: 12)

            switch settings.selectedProvider {
            case .overview:
                overviewContent
            case .opencode:
                openCodeContent
            case .cursor:
                cursorContent
            case .grok:
                grokContent
            }

            Divider().padding(.vertical, 6)

            menuActions
        }
        .padding(12)
        .frame(width: 420)
        .animation(.easeInOut(duration: 0.15), value: settings.selectedProvider)
        .onAppear {
            poller.menuIsOpen = true
            openCodePoller.menuIsOpen = true
            cursorPoller.menuIsOpen = true
            Task { await refreshActivePoller() }
        }
        .onDisappear {
            poller.menuIsOpen = false
            openCodePoller.menuIsOpen = false
            cursorPoller.menuIsOpen = false
        }
        .onChange(of: settings.selectedProvider) { _, _ in
            Task { await refreshActivePoller() }
        }
        .onChange(of: settings.showOpenCodeBarInMenuBar) { _, enabled in
            if enabled { Task { await openCodePoller.refreshNow() } }
        }
        .onChange(of: settings.showCursorBarInMenuBar) { _, enabled in
            if enabled { Task { await cursorPoller.refreshNow() } }
        }
    }

    private func refreshActivePoller() async {
        // Menu bar always shows Grok, so always refresh it.
        async let grok: Void = poller.refreshNow()
        async let openCode: Void = {
            if settings.needsOpenCodePolling {
                await openCodePoller.refreshNow()
            }
        }()
        async let cursor: Void = {
            if settings.needsCursorPolling {
                await cursorPoller.refreshNow()
            }
        }()
        _ = await (grok, openCode, cursor)
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

    @ViewBuilder
    private var cursorContent: some View {
        CursorPanelView(
            poller: cursorPoller,
            auth: cursorAuth,
            openSignIn: openCursorSignIn
        )
    }

    private var overviewContent: some View {
        OverviewPanelView(
            grokPoller: poller,
            openCodePoller: openCodePoller,
            cursorPoller: cursorPoller,
            grokHourly: grokHourly,
            grokAuth: auth,
            openCodeAuth: openCodeAuth,
            cursorAuth: cursorAuth,
            openGrokSignIn: openSignIn,
            openOpenCodeSignIn: openOpenCodeSignIn,
            openCursorSignIn: openCursorSignIn
        )
    }

    private var menuActions: some View {
        VStack(spacing: 2) {
            panelButton("Refresh Now", shortcut: "⌘R") {
                Task { await refreshActivePoller() }
            }
            .keyboardShortcut("r", modifiers: [.command])

            switch settings.selectedProvider {
            case .grok:
                Toggle(isOn: $settings.showCategoriesInMenuBar) {
                    toggleLabel("Show Categories in Menu Bar", isOn: settings.showCategoriesInMenuBar)
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .font(PanelTypography.body)

                Toggle(isOn: $settings.showGrokBarInMenuBar) {
                    toggleLabel("Show Bar Graph in Menu Bar", isOn: settings.showGrokBarInMenuBar)
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .font(PanelTypography.body)

                if !auth.isSignedIn {
                    panelButton("Sign In…", shortcut: nil, action: openSignIn)
                }
            case .opencode:
                Toggle(isOn: $settings.showOpenCodeBarInMenuBar) {
                    toggleLabel("Show Bar Graph in Menu Bar", isOn: settings.showOpenCodeBarInMenuBar)
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .font(PanelTypography.body)
            case .cursor:
                Toggle(isOn: $settings.showCursorBarInMenuBar) {
                    toggleLabel("Show Bar Graph in Menu Bar", isOn: settings.showCursorBarInMenuBar)
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .font(PanelTypography.body)
            case .overview:
                EmptyView()
            }

            Divider().padding(.vertical, 4)

            panelButton("Open TokenMon…", shortcut: "⌘O", action: openPreferences)
                .keyboardShortcut("o", modifiers: [.command])

            if let url = settings.selectedProvider.websiteURL {
                panelButton("Visit website", shortcut: nil) {
                    NSWorkspace.shared.open(url)
                }
            }

            if settings.selectedProvider == .grok {
                panelButton("Usage History…", shortcut: nil, action: openCharts)
            }

            Divider().padding(.vertical, 4)

            panelButton("Quit TokenMon", shortcut: "⌘Q") {
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
