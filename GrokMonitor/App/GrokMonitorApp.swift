import SwiftUI
import AppKit
import Combine

@main
struct GrokMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRoot(model: model)
        } label: {
            MenuBarLabelContainer(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Grok Monitor", id: "preferences") {
            PreferencesRoot(model: model)
        }
        .defaultSize(width: 480, height: 640)

        Window("Usage History", id: "charts") {
            HistoryChartView(history: model.history)
        }
        .defaultSize(width: 640, height: 480)

        Window("Sign in to Grok", id: "signin") {
            SignInView(auth: model.auth) {
                Task { await model.poller.refreshNow() }
                AppDelegate.hideDockIfNoWindows()
            }
            .background(Color.clear
                .frame(width: 0, height: 0)
                .onDisappear {
                    AppDelegate.hideDockIfNoWindows()
                }
            )
        }
        .defaultSize(width: 920, height: 700)
        .windowResizability(.contentMinSize)

        Window("Sign in to OpenCode", id: "opencode-signin") {
            OpenCodeSignInView(auth: model.openCodeAuth) {
                Task { await model.openCodePoller.refreshNow() }
                AppDelegate.hideDockIfNoWindows()
            }
            .background(Color.clear
                .frame(width: 0, height: 0)
                .onDisappear {
                    AppDelegate.hideDockIfNoWindows()
                }
            )
        }
        .defaultSize(width: 920, height: 700)
        .windowResizability(.contentMinSize)
    }
}

/// Shared app services owned for the process lifetime.
@MainActor
final class AppModel: ObservableObject {
    let auth: AuthSessionService
    let openCodeAuth: OpenCodeAuthSession
    let settings = AppSettings()
    let history = HistoryStore()
    let notifier = ThresholdNotifier()
    let grokHourly = GrokHourlyActivityStore()
    let poller: UsagePoller
    let openCodePoller: OpenCodeUsagePoller

    private var cancellables = Set<AnyCancellable>()

    init() {
        let auth = AuthSessionService()
        let openCodeAuth = OpenCodeAuthSession()
        self.auth = auth
        self.openCodeAuth = openCodeAuth
        poller = UsagePoller(
            auth: auth,
            history: history,
            settings: settings,
            notifier: notifier,
            grokHourly: grokHourly
        )
        openCodePoller = OpenCodeUsagePoller(settings: settings, auth: openCodeAuth)
        forwardChanges(from: settings)
        forwardChanges(from: poller)
        forwardChanges(from: openCodePoller)
        forwardChanges(from: auth)
        forwardChanges(from: openCodeAuth)
        forwardChanges(from: history)
        forwardChanges(from: grokHourly)
        notifier.requestAuthorizationIfNeeded()
        poller.start()
        openCodePoller.start()
    }

    /// MenuBarExtra label only observes `AppModel`; forward child updates.
    private func forwardChanges(from object: some ObservableObject) {
        object.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
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
            settings: model.settings,
            history: model.history,
            grokHourly: model.grokHourly,
            openPreferences: {
                AppDelegate.revealWindow()
                openWindow(id: "preferences")
            },
            openCharts: {
                AppDelegate.revealWindow()
                openWindow(id: "charts")
            },
            openSignIn: {
                AppDelegate.revealWindow()
                openWindow(id: "signin")
            },
            openOpenCodeSignIn: {
                AppDelegate.revealWindow()
                openWindow(id: "opencode-signin")
            }
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
            settings: model.settings,
            history: model.history,
            poller: model.poller,
            openCodePoller: model.openCodePoller,
            openSignIn: {
                AppDelegate.revealWindow()
                openWindow(id: "signin")
            },
            openOpenCodeSignIn: {
                AppDelegate.revealWindow()
                openWindow(id: "opencode-signin")
            }
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
            provider: .grok,
            isSignedIn: model.auth.isSignedIn && !model.auth.needsSignIn,
            showBar: model.settings.showBarGraphInMenuBar,
            showCategories: model.settings.showCategoriesInMenuBar,
            visibleProductIDs: model.settings.visibleProductIDs
        )
    }
}
