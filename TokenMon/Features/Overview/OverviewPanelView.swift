import AppKit
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

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        return "v\(v)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                Text("Token Monitor")
                    .font(PanelTypography.title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(appVersion)
                    .font(PanelTypography.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            grokUsageCard
            openCodeUsageCard
            cursorUsageCard
            signInHints

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

    private var grokUsageCard: some View {
        let percent = grokPoller.snapshot?.usedPercent ?? 0
        let resetsAt = grokPoller.snapshot?.resetsAt
        return PanelCard {
            HStack(alignment: .center, spacing: 8) {
                Image(nsImage: ProviderLogo.image(for: .grok))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                Text("Grok")
                    .font(PanelTypography.title)
                    .foregroundStyle(.primary)
                Text("— Weekly")
                    .font(PanelTypography.micro)
                    .fontWeight(.semibold)
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                Spacer()
                PanelPill(text: "\(Int(percent.rounded()))% used")
            }
            GeometryReader { geo in
                let w = max(0, geo.size.width * CGFloat(Percent.clamp(percent) / 100))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(ConcentricUsageRingView.grokColor).frame(width: w)
                }
            }
            .frame(height: 8)
            if let resetsAt {
                Text("Resets \(Format.resetDate(resetsAt, dateFormat: "EEE dd MMMM h:mma"))")
                    .font(PanelTypography.caption)
                    .foregroundStyle(.tertiary)
            } else if grokPoller.snapshot == nil {
                Text("No Grok data yet")
                    .font(PanelTypography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var openCodeUsageCard: some View {
        let monthly = openCodePoller.snapshot?.windows.first { $0.kind == .monthly }
        let percent = monthly?.usedPercent ?? openCodePoller.snapshot?.monthlyUsedPercent ?? 0
        let resetsAt = monthly?.resetsAt
        return PanelCard {
            HStack(alignment: .center, spacing: 8) {
                Image(nsImage: ProviderLogo.image(for: .opencode))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                Text("OpenCode")
                    .font(PanelTypography.title)
                    .foregroundStyle(.primary)
                Text("— Monthly")
                    .font(PanelTypography.micro)
                    .fontWeight(.semibold)
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                Spacer()
                PanelPill(text: "\(Int(percent.rounded()))% used")
            }
            GeometryReader { geo in
                let w = max(0, geo.size.width * CGFloat(Percent.clamp(percent) / 100))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(ModelPalette.purple.color).frame(width: w)
                }
            }
            .frame(height: 8)
            if let resetsAt {
                Text("Resets \(Format.resetDate(resetsAt, dateFormat: "EEE dd MMMM h:mma"))")
                    .font(PanelTypography.caption)
                    .foregroundStyle(.tertiary)
            } else if openCodePoller.snapshot == nil {
                Text("No OpenCode data yet")
                    .font(PanelTypography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var cursorUsageCard: some View {
        let percent = cursorPoller.snapshot?.usedPercent ?? 0
        let resetsAt = cursorPoller.snapshot?.resetsAt
        return PanelCard {
            HStack(alignment: .center, spacing: 8) {
                Image(nsImage: ProviderLogo.image(for: .cursor))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                Text("Cursor")
                    .font(PanelTypography.title)
                    .foregroundStyle(.primary)
                Text("— Monthly")
                    .font(PanelTypography.micro)
                    .fontWeight(.semibold)
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                Spacer()
                PanelPill(text: "\(Int(percent.rounded()))% used")
            }
            GeometryReader { geo in
                let w = max(0, geo.size.width * CGFloat(Percent.clamp(percent) / 100))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(ConcentricUsageRingView.cursorColor).frame(width: w)
                }
            }
            .frame(height: 8)
            if let resetsAt {
                Text("Resets \(Format.resetDate(resetsAt, dateFormat: "EEE dd MMMM h:mma"))")
                    .font(PanelTypography.caption)
                    .foregroundStyle(.tertiary)
            } else if cursorPoller.snapshot == nil {
                Text("No Cursor data yet")
                    .font(PanelTypography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var signInHints: some View {
        if !grokAuth.isSignedIn || grokAuth.needsSignIn {
            Button("Sign In to Grok…") { openGrokSignIn() }
                .font(PanelTypography.caption)
                .padding(.top, 2)
        }
        if openCodeAuth.needsSignIn && openCodePoller.snapshot == nil {
            Button("Sign In to OpenCode…") { openOpenCodeSignIn() }
                .font(PanelTypography.caption)
                .padding(.top, 2)
        }
        if cursorAuth.needsSignIn && cursorPoller.snapshot == nil {
            Button("Sign In to Cursor…") { openCursorSignIn() }
                .font(PanelTypography.caption)
                .padding(.top, 2)
        }
    }
}
