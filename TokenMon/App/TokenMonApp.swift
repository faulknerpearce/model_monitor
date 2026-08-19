import AppKit
import Combine
import SwiftUI

@main
struct TokenMonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRoot(model: model)
        } label: {
            MenuBarLabelContainer(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("TokenMon", id: "preferences") {
            PreferencesRoot(model: model)
        }
        .defaultSize(width: 480, height: 640)

        Window("Usage History", id: "charts") {
            HistoryChartView(history: model.history)
        }
        .defaultSize(width: 640, height: 480)

        Window("Sign in to Grok", id: AppWindowID.grokSignIn.rawValue) {
            SignInView(auth: model.auth) {
                Task { await model.poller.refreshNow() }
                AppDelegate.hideDockIfNoWindows()
            }
            .signInWindowChrome()
        }
        .defaultSize(width: 920, height: 700)
        .windowResizability(.contentMinSize)

        Window("Sign in to OpenCode", id: AppWindowID.openCodeSignIn.rawValue) {
            OpenCodeSignInView(auth: model.openCodeAuth) {
                Task { await model.openCodePoller.refreshNow() }
                AppDelegate.hideDockIfNoWindows()
            }
            .signInWindowChrome()
        }
        .defaultSize(width: 920, height: 700)
        .windowResizability(.contentMinSize)

        Window("Sign in to Cursor", id: AppWindowID.cursorSignIn.rawValue) {
            CursorSignInView(auth: model.cursorAuth) {
                Task { await model.cursorPoller.refreshNow() }
                AppDelegate.hideDockIfNoWindows()
            }
            .signInWindowChrome()
        }
        .defaultSize(width: 920, height: 700)
        .windowResizability(.contentMinSize)
    }
}

enum AppWindowID: String {
    case preferences
    case charts
    case grokSignIn = "signin"
    case openCodeSignIn = "opencode-signin"
    case cursorSignIn = "cursor-signin"
}

private extension View {
    func signInWindowChrome() -> some View {
        background(
            Color.clear
                .frame(width: 0, height: 0)
                .onDisappear {
                    AppDelegate.hideDockIfNoWindows()
                }
        )
    }
}

/// Shared app services owned for the process lifetime.
@MainActor
final class AppModel: ObservableObject {
    let auth: AuthSessionService
    let openCodeAuth: OpenCodeAuthSession
    let cursorAuth: CursorAuthSession
    let settings = AppSettings()
    let history = HistoryStore()
    let notifier = ThresholdNotifier()
    let grokHourly = GrokHourlyActivityStore()
    let poller: UsagePoller
    let openCodePoller: OpenCodeUsagePoller
    let cursorPoller: CursorUsagePoller
    let providers: ProviderRegistry

    private var cancellables = Set<AnyCancellable>()

    init() {
        let auth = AuthSessionService()
        let openCodeAuth = OpenCodeAuthSession()
        let cursorAuth = CursorAuthSession()
        self.auth = auth
        self.openCodeAuth = openCodeAuth
        self.cursorAuth = cursorAuth
        poller = UsagePoller(
            auth: auth,
            history: history,
            settings: settings,
            notifier: notifier,
            grokHourly: grokHourly
        )
        openCodePoller = OpenCodeUsagePoller(settings: settings, auth: openCodeAuth)
        cursorPoller = CursorUsagePoller(settings: settings, auth: cursorAuth)
        providers = ProviderRegistry(
            grok: poller,
            openCode: openCodePoller,
            cursor: cursorPoller
        )
        forwardChanges(from: settings)
        forwardChanges(from: history)
        forwardChanges(from: grokHourly)
        for (_, providerPoller) in providers.all {
            forwardChanges(from: providerPoller)
        }
        forwardChanges(from: auth)
        forwardChanges(from: openCodeAuth)
        forwardChanges(from: cursorAuth)
        notifier.requestAuthorizationIfNeeded()
        providers.startAll()
    }

    /// MenuBarExtra label only observes `AppModel`; forward child updates.
    private func forwardChanges(from object: some ObservableObject) {
        object.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func openWindow(_ id: AppWindowID, openWindow: OpenWindowAction) {
        AppDelegate.revealWindow()
        openWindow(id: id.rawValue)
    }
}

struct MenuBarRoot: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarPanelView(
            auth: model.auth,
            poller: model.poller,
            openCodeAuth: model.openCodeAuth,
            openCodePoller: model.openCodePoller,
            cursorAuth: model.cursorAuth,
            cursorPoller: model.cursorPoller,
            settings: model.settings,
            history: model.history,
            grokHourly: model.grokHourly,
            openPreferences: { model.openWindow(.preferences, openWindow: openWindow) },
            openCharts: { model.openWindow(.charts, openWindow: openWindow) },
            openSignIn: { model.openWindow(.grokSignIn, openWindow: openWindow) },
            openOpenCodeSignIn: { model.openWindow(.openCodeSignIn, openWindow: openWindow) },
            openCursorSignIn: { model.openWindow(.cursorSignIn, openWindow: openWindow) }
        )
    }
}

private struct PreferencesRoot: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        PreferencesView(
            auth: model.auth,
            openCodeAuth: model.openCodeAuth,
            cursorAuth: model.cursorAuth,
            settings: model.settings,
            history: model.history,
            poller: model.poller,
            openCodePoller: model.openCodePoller,
            cursorPoller: model.cursorPoller,
            openSignIn: { model.openWindow(.grokSignIn, openWindow: openWindow) },
            openOpenCodeSignIn: { model.openWindow(.openCodeSignIn, openWindow: openWindow) },
            openCursorSignIn: { model.openWindow(.cursorSignIn, openWindow: openWindow) }
        )
    }
}

/// Observes nested services so the menu bar label refreshes on poll/settings updates.
struct MenuBarLabelContainer: View {
    @ObservedObject var model: AppModel

    var body: some View {
        MenuBarLabelView(
            snapshot: model.poller.snapshot,
            openCodeSnapshot: model.openCodePoller.snapshot,
            cursorSnapshot: model.cursorPoller.snapshot,
            isGrokSignedIn: model.auth.isSignedIn && !model.auth.needsSignIn,
            showGrokBar: model.settings.showGrokBarInMenuBar,
            showGrokCategories: model.settings.showCategoriesInMenuBar,
            showOpenCodeBar: model.settings.showOpenCodeBarInMenuBar,
            showCursorBar: model.settings.showCursorBarInMenuBar,
            visibleProductIDs: model.settings.visibleProductIDs
        )
    }
}
