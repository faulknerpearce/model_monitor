import SwiftUI

struct OverviewPanelView: View {
    @ObservedObject var grokPoller: UsagePoller
    @ObservedObject var openCodePoller: OpenCodeUsagePoller
    @ObservedObject var cursorPoller: CursorUsagePoller
    @ObservedObject var grokHourly: GrokHourlyActivityStore
    @ObservedObject var grokAuth: AuthSessionService
    @ObservedObject var openCodeAuth: OpenCodeAuthSession
    @ObservedObject var cursorAuth: CursorAuthSession

    var openGrokSignIn: () -> Void
    var openOpenCodeSignIn: () -> Void
    var openCursorSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProviderHeaderLabel(provider: .overview, title: "Overview")

            PanelCard {
                PanelSectionHeader(title: "Usage rings")
                ConcentricUsageRingView(
                    grokPercent: grokPoller.snapshot?.usedPercent,
                    openCodePercent: openCodePoller.snapshot?.monthlyUsedPercent,
                    cursorPercent: cursorPoller.snapshot?.usedPercent
                )
                signInHints
            }

            PanelCard {
                PanelSectionHeader(title: "Today")
                OverviewHourlyUsageChart(usage: providerHourlyUsage)
            }
        }
    }

    private var providerHourlyUsage: ProviderDayHourlyUsage? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())

        let openCodeWeights: (openCodeGo: [Double], openCodeZen: [Double]) = {
            guard let hourly = openCodePoller.dayHourlyUsage,
                  calendar.isDate(hourly.dayStart, inSameDayAs: dayStart),
                  hourly.hours.count == 24
            else {
                let empty = Array(repeating: 0.0, count: 24)
                return (empty, empty)
            }
            let monthlyLimit = openCodePoller.snapshot?.windows
                .first { $0.kind == .monthly }?.limitUSD
                ?? OpenCodeWindowKind.monthly.defaultLimitUSD
            return hourly.overviewProviderQuotaHourWeights(monthlyLimitUSD: monthlyLimit)
        }()

        let openCodeCostWeights: (openCodeGo: [Double], openCodeZen: [Double]) = {
            guard let hourly = openCodePoller.dayHourlyUsage,
                  calendar.isDate(hourly.dayStart, inSameDayAs: dayStart),
                  hourly.hours.count == 24
            else {
                let empty = Array(repeating: 0.0, count: 24)
                return (empty, empty)
            }
            let raw = hourly.overviewProviderHourWeights()
            return (raw.openCodeGo, raw.openCodeZen)
        }()

        let openCodeTokenWeights: (openCodeGo: [Int64], openCodeZen: [Int64]) = {
            guard let hourly = openCodePoller.dayHourlyUsage,
                  calendar.isDate(hourly.dayStart, inSameDayAs: dayStart),
                  hourly.hours.count == 24
            else {
                let empty = Array(repeating: Int64(0), count: 24)
                return (empty, empty)
            }
            let raw = hourly.overviewProviderHourTokenCounts()
            return (raw.openCodeGo, raw.openCodeZen)
        }()

        let grokPollWeights: [Double] = {
            if calendar.isDate(grokHourly.dayStart, inSameDayAs: dayStart),
               grokHourly.hourWeights.count == 24 {
                return grokHourly.hourWeights
            }
            return Array(repeating: 0, count: 24)
        }()

        let cursorWeights: [Double] = {
            guard let hourly = cursorPoller.dayHourlyUsage,
                  calendar.isDate(hourly.dayStart, inSameDayAs: dayStart),
                  hourly.quotaHourWeights.count == 24
            else {
                return Array(repeating: 0, count: 24)
            }
            return hourly.quotaHourWeights
        }()

        let cursorTokenWeights: [Int64] = {
            guard let hourly = cursorPoller.dayHourlyUsage,
                  calendar.isDate(hourly.dayStart, inSameDayAs: dayStart),
                  hourly.hourTokenWeights.count == 24
            else {
                return Array(repeating: 0, count: 24)
            }
            return hourly.hourTokenWeights
        }()

        // Official Grok pool deltas plus OpenCode plan quota deltas.
        // Direct BYOK Grok-through-OpenCode usage has no shared quota denominator.
        let hourCostUSD = zip(openCodeCostWeights.openCodeGo, openCodeCostWeights.openCodeZen).map(+)

        let built = ProviderDayHourlyUsage.build(
            dayStart: dayStart,
            grokHourWeights: grokPollWeights,
            openCodeGoHourWeights: openCodeWeights.openCodeGo,
            openCodeZenHourWeights: openCodeWeights.openCodeZen,
            cursorHourWeights: cursorWeights,
            hourCostUSD: hourCostUSD,
            openCodeGoHourTokens: openCodeTokenWeights.openCodeGo,
            openCodeZenHourTokens: openCodeTokenWeights.openCodeZen,
            cursorHourTokens: cursorTokenWeights
        )
        return built.isEmpty ? nil : built
    }

    @ViewBuilder
    private var signInHints: some View {
        if !grokAuth.isSignedIn || grokAuth.needsSignIn {
            Button("Sign In to Grok…") { openGrokSignIn() }
                .font(PanelTypography.caption)
                .padding(.top, 10)
        }
        if openCodeAuth.needsSignIn && openCodePoller.snapshot == nil {
            Button("Sign In to OpenCode…") { openOpenCodeSignIn() }
                .font(PanelTypography.caption)
                .padding(.top, 10)
        }
        if cursorAuth.needsSignIn && cursorPoller.snapshot == nil {
            Button("Sign In to Cursor…") { openCursorSignIn() }
                .font(PanelTypography.caption)
                .padding(.top, 10)
        }
    }
}
