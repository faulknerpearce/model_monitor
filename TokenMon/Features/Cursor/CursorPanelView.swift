import SwiftUI

struct CursorPanelView: View {
    @ObservedObject var poller: CursorUsagePoller
    @ObservedObject var auth: CursorAuthSession
    let openSignIn: () -> Void

    var body: some View {
        if auth.needsSignIn && poller.snapshot == nil {
            signedOut
        } else if let snapshot = poller.snapshot {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ProviderHeaderLabel(provider: .cursor, title: "Cursor")
                    Spacer()
                    Text(snapshot.displayPlanName)
                        .font(PanelTypography.captionMedium)
                        .foregroundStyle(.secondary)
                }

                PanelCard {
                    PanelSectionHeader(title: "Usage")
                    ForEach(snapshot.pools) { pool in
                        CursorPoolBar(pool: pool)
                    }
                }

                if let days = poller.dailyBudgetDays, !days.isEmpty {
                    PanelCard {
                        DailyBudgetBarsView(days: days, accent: ConcentricUsageRingView.cursorColor)
                    }
                }

                if let stats = snapshot.costStats {
                    VStack(alignment: .leading, spacing: 0) {
                        PanelSectionHeader(title: "Stats")
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                        CursorStatsGrid(stats: stats)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
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

    var body: some View {
        MetricStatGrid([
            MetricStat(title: "Monthly spend", value: Format.usd(stats.meteredCycleUSD)),
            MetricStat(title: "Total tokens", value: Format.tokens(stats.cycleTokens)),
            MetricStat(title: "Input tokens", value: Format.tokens(stats.cycleInputTokens)),
            MetricStat(title: "Output tokens", value: Format.tokens(stats.cycleOutputTokens))
        ])
    }
}
