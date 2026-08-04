import SwiftUI

struct CursorPanelView: View {
    @ObservedObject var poller: CursorUsagePoller
    @ObservedObject var auth: CursorAuthSession
    var openSignIn: () -> Void

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
            HStack(spacing: 0) {
                metricColumn(title: "Monthly tokens", value: Self.formatTokens(stats.cycleTokens))
                verticalDivider
                metricColumn(title: "Daily tokens", value: Self.formatTokens(stats.todayTokens))
            }

            horizontalDivider

            HStack(spacing: 0) {
                metricColumn(title: "20-day spend", value: Self.formatUSD(stats.last20dUSD))
                verticalDivider
                metricColumn(title: "Top model", value: topModel ?? "Unavailable", monospaced: false)
            }
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

    private var verticalDivider: some View {
        Divider()
            .frame(height: 48)
            .padding(.horizontal, 14)
    }

    private var horizontalDivider: some View {
        Divider()
            .padding(.vertical, 10)
    }

    private func metricColumn(title: String, value: String, monospaced: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(PanelTypography.captionMedium)
                .foregroundStyle(.secondary)
            valueText(value, monospaced: monospaced)
                .font(PanelTypography.hero)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    }

    @ViewBuilder
    private func valueText(_ value: String, monospaced: Bool) -> some View {
        if monospaced {
            Text(value).monospacedDigit()
        } else {
            Text(value)
        }
    }

    private static func formatTokens(_ count: Int64) -> String {
        let value = Double(count)
        if value >= 1_000_000_000 {
            return String(format: "%.1fB", value / 1_000_000_000)
        }
        if value >= 1_000_000 {
            let millions = value / 1_000_000
            return millions >= 10
                ? String(format: "%.0fM", millions)
                : String(format: "%.1fM", millions)
        }
        if value >= 1_000 {
            return String(format: "%.0fK", value / 1_000)
        }
        return "\(count)"
    }

    private static func formatUSD(_ usd: Double) -> String {
        Format.usdCurrency.string(from: NSNumber(value: usd)) ?? "$0"
    }
}
