import SwiftUI

struct OpenCodePanelView: View {
    @ObservedObject var poller: OpenCodeUsagePoller
    @ObservedObject var auth: OpenCodeAuthSession
    var openSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if auth.needsSignIn && poller.snapshot == nil {
                signedOut
            } else if let snapshot = poller.snapshot {
                HStack {
                    ProviderHeaderLabel(provider: .opencode, title: "OpenCode Go")
                    Spacer()
                    if let source = poller.dataSourceLabel {
                        Text(source)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(snapshot.isEstimated ? Color.orange : Color.secondary)
                    }
                }

                ForEach(snapshot.windows) { window in
                    OpenCodeLimitBar(window: window)
                }

                if snapshot.isEstimated {
                    Text("Estimated from local sessions — sign in for console accuracy.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                if !snapshot.models.isEmpty {
                    Divider().padding(.vertical, 2)

                    Text(snapshot.modelsWindowLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        ForEach(snapshot.models) { model in
                            OpenCodeModelRow(model: model)
                        }
                    }
                }

                if auth.needsSignIn || poller.lastError != nil {
                    if let err = poller.lastError {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Button(auth.needsSignIn ? "Sign In to OpenCode…" : "Sign In Again…") {
                        openSignIn()
                    }
                    .font(.system(size: 12))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ProviderHeaderLabel(provider: .opencode, title: "OpenCode Go")
                    Text(poller.isRefreshing ? "Refreshing…" : (poller.lastError ?? "No usage data yet."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if auth.needsSignIn {
                        Button("Sign In to OpenCode…") { openSignIn() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProviderHeaderLabel(provider: .opencode, title: "OpenCode Go")
            Text("Sign in to the OpenCode console to load official rolling, weekly, and monthly usage.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Sign In to OpenCode…") { openSignIn() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OpenCodeModelRow: View {
    let model: OpenCodeModelUsage

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(model.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
            Spacer()
            Text("\(Int(model.percentOfWindow.rounded()))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(Format.usdCurrency.string(from: NSNumber(value: model.costUSD)) ?? "")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
    }

    private var dotColor: Color {
        let c = ModelPalette.sRGB(forProvider: model.providerID, seed: model.id)
        return Color(red: c.red, green: c.green, blue: c.blue)
    }
}
