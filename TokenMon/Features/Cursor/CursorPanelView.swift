import SwiftUI

struct CursorPanelView: View {
    @ObservedObject var poller: CursorUsagePoller
    @ObservedObject var auth: CursorAuthSession
    let openSignIn: () -> Void

    var body: some View {
        if auth.needsSignIn && poller.snapshot == nil {
            signedOut
        } else if let snapshot = poller.snapshot {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ProviderHeaderLabel(provider: .cursor, title: "Cursor")
                    Spacer()
                    Text(snapshot.displayPlanName)
                        .font(PanelTypography.captionMedium)
                        .foregroundStyle(.secondary)
                }

                PanelSectionDivider()

                VStack(alignment: .leading, spacing: 10) {
                    PanelSectionHeader(title: "Usage")
                    ForEach(snapshot.pools) { pool in
                        CursorPoolBar(pool: pool)
                    }
                }

                if let stats = snapshot.costStats {
                    PanelSectionDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        PanelSectionHeader(title: "Stats")
                        CursorStatsGrid(stats: stats, topModel: snapshot.mostUsedModel)
                    }
                }

                if auth.needsSignIn || poller.lastError != nil {
                    if let err = poller.lastError {
                        Text(err)
                            .font(PanelTypography.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    Button(auth.needsSignIn ? "Sign In to Cursor…" : "Sign In Again…") {
                        openSignIn()
                    }
                    .font(PanelTypography.body)
                    .padding(.top, 8)
                }
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
        MetricStatGrid([
            MetricStat(title: "Monthly tokens", value: Format.tokens(stats.cycleTokens)),
            MetricStat(title: "Daily tokens", value: Format.tokens(stats.todayTokens)),
            MetricStat(title: "20-day spend", value: Format.usd(stats.last20dUSD)),
            MetricStat(title: "Top model", value: topModel ?? "Unavailable", monospaced: false)
        ])
    }
}
