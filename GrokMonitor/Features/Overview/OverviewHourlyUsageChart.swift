import SwiftUI

/// Today’s hourly Grok vs OpenCode usage — dashboard-style floating bars.
struct OverviewHourlyUsageChart: View {
    let usage: ProviderDayHourlyUsage?

    private let trackHeight: CGFloat = 96
    private let barWidth: CGFloat = 20
    private static let firstHour = 6
    private static let lastHour = 22 // 10pm

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hourly use")
                    .font(PanelTypography.section)
                Spacer()
                Text(dayCaption)
                    .font(PanelTypography.caption)
                    .foregroundStyle(.secondary)
            }

            if let usage, visibleHours(usage).contains(where: \.hasActivity) {
                hourBars(usage)
                legend
            } else {
                Text("No Grok or OpenCode activity yet today.")
                    .font(PanelTypography.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            }
        }
    }

    private var dayCaption: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        if let usage {
            return formatter.string(from: usage.dayStart)
        }
        return formatter.string(from: Calendar.current.startOfDay(for: Date()))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(title: "Grok", color: ConcentricUsageRingView.grokColor)
            legendItem(title: "OpenCode", color: ConcentricUsageRingView.openCodeColor)
            Spacer(minLength: 0)
        }
    }

    private func legendItem(title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(PanelTypography.micro)
                .foregroundStyle(.secondary)
        }
    }

    private func visibleHours(_ usage: ProviderDayHourlyUsage) -> [ProviderHourUsage] {
        usage.hours.filter { $0.hour >= Self.firstHour && $0.hour <= Self.lastHour }
    }

    private func hourBars(_ usage: ProviderDayHourlyUsage) -> some View {
        let hours = visibleHours(usage)
        let maxActivity = max(hours.map(\.activity).max() ?? 0, 0.0001)

        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(hours) { hour in
                hourColumn(hour, maxActivity: maxActivity)
            }
        }
        .frame(height: trackHeight + 18)
    }

    private func hourColumn(_ hour: ProviderHourUsage, maxActivity: Double) -> some View {
        let fillHeight = trackHeight * CGFloat(Self.heightFraction(activity: hour.activity, maxActivity: maxActivity))
        let showAxis = [Self.firstHour, 9, 12, 15, 18, Self.lastHour].contains(hour.hour)

        return VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: barWidth, height: 3)

                if hour.hasActivity {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if hour.openCodeSharePercent > 0.5 {
                            let h = max(2, fillHeight * CGFloat(hour.openCodeSharePercent / 100))
                            Rectangle()
                                .fill(ConcentricUsageRingView.openCodeColor)
                                .frame(width: barWidth, height: h)
                        }
                        if hour.grokSharePercent > 0.5 {
                            let h = max(2, fillHeight * CGFloat(hour.grokSharePercent / 100))
                            Rectangle()
                                .fill(ConcentricUsageRingView.grokColor)
                                .frame(width: barWidth, height: h)
                        }
                    }
                    .frame(width: barWidth, height: max(fillHeight, 4), alignment: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
            .frame(height: trackHeight, alignment: .bottom)
            .help(hourHelp(hour))

            Text(showAxis ? Self.axisLabel(for: hour.hour) : " ")
                .font(PanelTypography.micro)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity)
    }

    /// Soft height curve so one spike doesn’t flatten the rest of the day.
    static func heightFraction(activity: Double, maxActivity: Double) -> Double {
        guard activity > 0, maxActivity > 0 else { return 0 }
        let linear = min(1, activity / maxActivity)
        let soft = sqrt(linear)
        return min(1, 0.35 * linear + 0.65 * soft)
    }

    private static func axisLabel(for hour: Int) -> String {
        switch hour {
        case 0: return "12am"
        case 12: return "12pm"
        case 1..<12: return "\(hour)am"
        default: return "\(hour - 12)pm"
        }
    }

    private func hourHelp(_ hour: ProviderHourUsage) -> String {
        guard hour.hasActivity else { return "" }
        let g = Int(hour.grokSharePercent.rounded())
        let o = Int(hour.openCodeSharePercent.rounded())
        if hour.costUSD > 0 {
            let amount: String
            if hour.costUSD >= 10 {
                amount = String(format: "$%.0f", hour.costUSD)
            } else if hour.costUSD >= 1 {
                amount = String(format: "$%.1f", hour.costUSD)
            } else {
                amount = String(format: "$%.2f", hour.costUSD)
            }
            return "\(hour.hourLabel): \(amount) · Grok \(g)% · OpenCode \(o)%"
        }
        return "\(hour.hourLabel): Grok \(g)% · OpenCode \(o)%"
    }
}
