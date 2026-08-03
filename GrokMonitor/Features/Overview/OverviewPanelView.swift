import SwiftUI

struct OverviewPanelView: View {
    @ObservedObject var grokPoller: UsagePoller
    @ObservedObject var openCodePoller: OpenCodeUsagePoller
    @ObservedObject var grokHourly: GrokHourlyActivityStore
    @ObservedObject var grokAuth: AuthSessionService
    @ObservedObject var openCodeAuth: OpenCodeAuthSession

    var openGrokSignIn: () -> Void
    var openOpenCodeSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly overview")
                .font(PanelTypography.title)

            VStack(alignment: .leading, spacing: 10) {
                Text("Usage rings")
                    .font(PanelTypography.section)
                    .foregroundStyle(.secondary)

                ConcentricUsageRingView(
                    grokPercent: grokPoller.snapshot?.usedPercent,
                    openCodePercent: openCodePoller.snapshot?.primaryUsedPercent
                )
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

            signInHints

            OverviewHourlyUsageChart(usage: providerHourlyUsage)
        }
    }

    private var providerHourlyUsage: ProviderDayHourlyUsage? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())

        let openCodeSplit: (openCode: [Double], grokViaOpenCode: [Double]) = {
            guard let hourly = openCodePoller.dayHourlyUsage, hourly.hours.count == 24 else {
                return (Array(repeating: 0, count: 24), Array(repeating: 0, count: 24))
            }
            return hourly.overviewProviderHourWeights()
        }()

        let grokPollWeights: [Double] = {
            if calendar.isDate(grokHourly.dayStart, inSameDayAs: dayStart),
               grokHourly.hourWeights.count == 24 {
                return grokHourly.hourWeights
            }
            return Array(repeating: 0, count: 24)
        }()

        // Official Grok pool deltas + Grok used via OpenCode harness (e.g. xai/grok-4.5).
        let grokWeights = zip(grokPollWeights, openCodeSplit.grokViaOpenCode).map(+)
        let hourCostUSD = zip(openCodeSplit.openCode, openCodeSplit.grokViaOpenCode).map(+)

        let built = ProviderDayHourlyUsage.build(
            dayStart: dayStart,
            grokHourWeights: grokWeights,
            openCodeHourWeights: openCodeSplit.openCode,
            hourCostUSD: hourCostUSD
        )
        return built.isEmpty ? nil : built
    }

    @ViewBuilder
    private var signInHints: some View {
        if !grokAuth.isSignedIn || grokAuth.needsSignIn {
            Button("Sign In to Grok…") { openGrokSignIn() }
                .font(PanelTypography.caption)
        }
        if openCodeAuth.needsSignIn && openCodePoller.snapshot == nil {
            Button("Sign In to OpenCode…") { openOpenCodeSignIn() }
                .font(PanelTypography.caption)
        }
    }
}
