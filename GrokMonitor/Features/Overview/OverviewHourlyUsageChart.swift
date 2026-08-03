import SwiftUI

/// Today’s hourly Grok vs OpenCode share — stacked provider bars (no model breakdown).
struct OverviewHourlyUsageChart: View {
    let usage: ProviderDayHourlyUsage?

    private let trackHeight: CGFloat = 108
    private let barWidth: CGFloat = 12
    private static let firstHour = 6
    private static let lastHour = 22 // 10pm

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hourly use")
                .font(.system(size: 12, weight: .semibold))

            Text(dayCaption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            if let usage, visibleHours(usage).contains(where: \.hasActivity) {
                hourBars(usage)
                legend
            } else {
                Text("No Grok or OpenCode activity yet today.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
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
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func visibleHours(_ usage: ProviderDayHourlyUsage) -> [ProviderHourUsage] {
        usage.hours.filter { $0.hour >= Self.firstHour && $0.hour <= Self.lastHour }
    }

    private func hourBars(_ usage: ProviderDayHourlyUsage) -> some View {
        let hours = visibleHours(usage)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                // Scale each bar to the peak so far (this hour + prior visible hours),
                // so early activity stays readable and later spikes still hit full height.
                let runningMax = hours[0...index].map(\.activity).max() ?? 0
                hourColumn(hour, scaleMax: max(runningMax, 0.0001))
            }
        }
        .frame(height: trackHeight + 16)
    }

    private func hourColumn(_ hour: ProviderHourUsage, scaleMax: Double) -> some View {
        let fillHeight = trackHeight * CGFloat(min(1, hour.activity / scaleMax))
        let showLabel = [Self.firstHour, 12, 18, Self.lastHour].contains(hour.hour)
        return VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: barWidth, height: trackHeight)

                if hour.hasActivity {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        // OpenCode bottom, Grok top — matches ring legend order visually.
                        if hour.openCodeSharePercent > 0.5 {
                            let h = max(1.5, fillHeight * CGFloat(hour.openCodeSharePercent / 100))
                            Rectangle()
                                .fill(ConcentricUsageRingView.openCodeColor)
                                .frame(width: barWidth, height: h)
                        }
                        if hour.grokSharePercent > 0.5 {
                            let h = max(1.5, fillHeight * CGFloat(hour.grokSharePercent / 100))
                            Rectangle()
                                .fill(ConcentricUsageRingView.grokColor)
                                .frame(width: barWidth, height: h)
                        }
                    }
                    .frame(width: barWidth, height: trackHeight, alignment: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            .frame(width: barWidth, height: trackHeight)
            .help(hourHelp(hour))

            Text(showLabel ? hour.hourLabel : " ")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
    }

    private func hourHelp(_ hour: ProviderHourUsage) -> String {
        guard hour.hasActivity else { return "" }
        let g = Int(hour.grokSharePercent.rounded())
        let o = Int(hour.openCodeSharePercent.rounded())
        return "\(hour.hourLabel): Grok \(g)% · OpenCode \(o)%"
    }
}
