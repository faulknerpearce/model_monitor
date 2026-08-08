import SwiftUI

struct CursorPanelView: View {
    @ObservedObject var poller: CursorUsagePoller
    @ObservedObject var auth: CursorAuthSession
    let openSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if auth.needsSignIn && poller.snapshot == nil {
                signedOut
            } else if let snapshot = poller.snapshot {
                HStack {
                    ProviderHeaderLabel(provider: .cursor, title: "Cursor")
                    Spacer()
                    Text(snapshot.displayPlanName)
                        .font(PanelTypography.captionMedium)
                        .foregroundStyle(.secondary)
                }

                ForEach(snapshot.pools) { pool in
                    CursorPoolBar(pool: pool)
                }

                if let stats = snapshot.costStats {
                    CursorStatsGrid(stats: stats, topModel: snapshot.mostUsedModel)
                }

                if auth.needsSignIn || poller.lastError != nil {
                    if let err = poller.lastError {
                        Text(err)
                            .font(PanelTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(auth.needsSignIn ? "Sign In to Cursor…" : "Sign In Again…") {
                        openSignIn()
                    }
                    .font(PanelTypography.body)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ProviderHeaderLabel(provider: .cursor, title: "Cursor")
                    Text(poller.isRefreshing ? "Refreshing…" : (poller.lastError ?? "No usage data yet."))
                        .font(PanelTypography.body)
                        .foregroundStyle(.secondary)
                    if auth.needsSignIn {
                        Button("Sign In to Cursor…") { openSignIn() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProviderHeaderLabel(provider: .cursor, title: "Cursor")
            Text("Sign in to cursor.com to load Total, Auto, and API usage.")
                .font(PanelTypography.body)
                .foregroundStyle(.secondary)
            Button("Sign In to Cursor…") { openSignIn() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CursorStatsGrid: View {
    let stats: CursorCostStats
    let topModel: String?

    var body: some View {
        VStack(spacing: 0) {
            MetricStatGrid([
                MetricStat(title: "Monthly tokens", value: Format.tokens(stats.cycleTokens)),
                MetricStat(title: "Daily tokens", value: Format.tokens(stats.todayTokens))
            ])

            Divider().padding(.vertical, 10)

            MetricStatGrid([
                MetricStat(title: "20-day spend", value: Format.usd(stats.last20dUSD)),
                MetricStat(title: "Top model", value: topModel ?? "Unavailable", monospaced: false)
            ])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}
