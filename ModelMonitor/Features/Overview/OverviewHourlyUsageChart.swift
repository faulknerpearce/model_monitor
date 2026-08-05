import SwiftUI

/// Today's hourly Grok / OpenCode Go / OpenCode Zen / Cursor usage.
struct OverviewHourlyUsageChart: View {
    let usage: ProviderDayHourlyUsage?

    private let trackHeight: CGFloat = 96
    private let barWidth: CGFloat = 20
    private static let firstHour = 6
    private static let lastHour = 22 // 10pm
    private static let openCodeGoColor = Color(
        red: ModelPalette.goPurple.red,
        green: ModelPalette.goPurple.green,
        blue: ModelPalette.goPurple.blue
    )
    private static let openCodeZenColor = Color(
        red: ModelPalette.zenOrange.red,
        green: ModelPalette.zenOrange.green,
        blue: ModelPalette.zenOrange.blue
    )

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
                Text("No Grok, OpenCode, or Cursor activity yet today.")
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
            legendItem(title: "Cursor", color: ConcentricUsageRingView.cursorColor)
            legendItem(title: "OpenCode Go", color: Self.openCodeGoColor)
            legendItem(title: "OpenCode Zen", color: Self.openCodeZenColor)
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
                    let segments = Self.segmentsSortedByShare(hour)
                    let segmentGap: CGFloat = segments.count > 1 ? 1 : 0
                    let availableHeight = max(
                        0,
                        fillHeight - segmentGap * CGFloat(max(0, segments.count - 1))
                    )

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        // Least used at top, most used at bottom.
                        VStack(spacing: segmentGap) {
                            ForEach(segments, id: \.id) { segment in
                                let segmentHeight = max(1, availableHeight * CGFloat(segment.sharePercent / 100))
                                Rectangle()
                                    .fill(segment.color)
                                    .frame(
                                        width: barWidth,
                                        height: segmentHeight
                                    )
                            }
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

    /// Scale bars proportionally to the largest visible hour.
    static func heightFraction(activity: Double, maxActivity: Double) -> Double {
        guard activity > 0, maxActivity > 0 else { return 0 }
        return min(1, activity / maxActivity)
    }

    /// Segments ascending by share so VStack places least used on top, most used on bottom.
    static func segmentsSortedByShare(_ hour: ProviderHourUsage) -> [HourBarSegment] {
        [
            HourBarSegment(id: "grok", sharePercent: hour.grokSharePercent, color: ConcentricUsageRingView.grokColor),
            HourBarSegment(id: "opencode-go", sharePercent: hour.openCodeGoSharePercent, color: Self.openCodeGoColor),
            HourBarSegment(id: "opencode-zen", sharePercent: hour.openCodeZenSharePercent, color: Self.openCodeZenColor),
            HourBarSegment(id: "cursor", sharePercent: hour.cursorSharePercent, color: ConcentricUsageRingView.cursorColor)
        ]
        .filter { $0.sharePercent > 0.5 }
        .sorted { lhs, rhs in
            if lhs.sharePercent != rhs.sharePercent {
                return lhs.sharePercent < rhs.sharePercent
            }
            return lhs.id < rhs.id
        }
    }

    struct HourBarSegment {
        let id: String
        let sharePercent: Double
        let color: Color
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
        let go = Int(hour.openCodeGoSharePercent.rounded())
        let zen = Int(hour.openCodeZenSharePercent.rounded())
        let c = Int(hour.cursorSharePercent.rounded())
        let shares = "Grok \(g)% · Go \(go)% · Zen \(zen)% · Cursor \(c)%"
        if hour.costUSD > 0 {
            let amount: String
            if hour.costUSD >= 10 {
                amount = String(format: "$%.0f", hour.costUSD)
            } else if hour.costUSD >= 1 {
                amount = String(format: "$%.1f", hour.costUSD)
            } else {
                amount = String(format: "$%.2f", hour.costUSD)
            }
            return "\(hour.hourLabel): \(amount) · \(shares)"
        }
        return "\(hour.hourLabel): \(shares)"
    }
}
