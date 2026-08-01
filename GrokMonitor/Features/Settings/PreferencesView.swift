import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct PreferencesView: View {
    @ObservedObject var auth: AuthSessionService
    @ObservedObject var openCodeAuth: OpenCodeAuthSession
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: HistoryStore
    @ObservedObject var poller: UsagePoller
    @ObservedObject var openCodePoller: OpenCodeUsagePoller
    var openSignIn: () -> Void
    var openOpenCodeSignIn: () -> Void
    @State private var exportError: String?

    var body: some View {
        Form {
            Section("Grok Account") {
                if auth.isSignedIn {
                    LabeledContent("Signed in as") {
                        Text(auth.accountEmail ?? "Grok account")
                    }
                    Button("Sign Out", role: .destructive) {
                        auth.signOut()
                        poller.clearSnapshot()
                    }
                    Button("Re-authenticate…") { openSignIn() }
                } else {
                    Text("Not signed in")
                        .foregroundStyle(.secondary)
                    Button("Sign In to grok.com…") { openSignIn() }
                }
                if let err = auth.lastAuthError {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }

            Section("OpenCode Account") {
                if openCodeAuth.isSignedIn {
                    LabeledContent("Signed in as") {
                        Text(openCodeAuth.accountEmail ?? "OpenCode account")
                    }
                    Button("Sign Out", role: .destructive) {
                        openCodeAuth.signOut()
                        openCodePoller.clearSnapshot()
                    }
                    Button("Re-authenticate…") { openOpenCodeSignIn() }
                } else {
                    Text("Not signed in")
                        .foregroundStyle(.secondary)
                    Button("Sign In to OpenCode…") { openOpenCodeSignIn() }
                }
                if let err = openCodeAuth.lastAuthError {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }

            Section("Menu Bar") {
                Toggle("Show Categories in Menu Bar", isOn: $settings.showCategoriesInMenuBar)
                Toggle("Show Bar Graph in Menu Bar", isOn: $settings.showBarGraphInMenuBar)
            }

            Section("Refresh") {
                Stepper(value: $settings.activePollSeconds, in: 15...300, step: 15) {
                    Text("While menu open: \(settings.activePollSeconds)s")
                }
                Stepper(value: $settings.idlePollSeconds, in: 60...3600, step: 60) {
                    Text("While idle: \(settings.idlePollSeconds)s")
                }
                if settings.selectedProvider == .opencode {
                    if let last = openCodePoller.lastRefreshedAt {
                        Text("Last refresh: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                    if let error = openCodePoller.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                } else {
                    if let last = poller.lastRefreshedAt {
                        Text("Last refresh: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                    if let error = poller.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }

            Section("Alerts") {
                Toggle("Notify when usage exceeds threshold", isOn: $settings.thresholdEnabled)
                if settings.thresholdEnabled {
                    Slider(value: $settings.thresholdPercent, in: 50...99, step: 1) {
                        Text("Threshold")
                    } minimumValueLabel: {
                        Text("50%")
                    } maximumValueLabel: {
                        Text("99%")
                    }
                    Text("Alert at \(Int(settings.thresholdPercent))% used")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Categories") {
                ForEach(ProductCatalog.knownIDs, id: \.self) { id in
                    Toggle(ProductCatalog.displayName(for: id), isOn: Binding(
                        get: { settings.visibleProductIDs.contains(id) },
                        set: { on in
                            if on { settings.visibleProductIDs.insert(id) }
                            else { settings.visibleProductIDs.remove(id) }
                        }
                    ))
                }
            }

            Section("System") {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            }

            Section("Data") {
                Button("Export CSV…") { export(.csv) }
                Button("Export JSON…") { export(.json) }
                Button("Clear Local History", role: .destructive) {
                    history.clear()
                }
                Text("Clearing history does not reset your SuperGrok weekly pool.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let exportError {
                Section {
                    Text(exportError).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 440, minHeight: 520)
        .onDisappear {
            AppDelegate.hideDockIfNoWindows()
        }
    }

    private func export(_ format: ExportService.Format) {
        do {
            let data = try ExportService.export(history.allSnapshots(), format: format)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .json]
            panel.nameFieldStringValue = format == .csv ? "grok-usage.csv" : "grok-usage.json"
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
            }
        } catch {
            exportError = error.localizedDescription
        }
    }
}
