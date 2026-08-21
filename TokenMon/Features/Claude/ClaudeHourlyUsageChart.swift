import SwiftUI

/// Today's Claude usage chart styled exactly like the Grok daily-use chart.
///
/// Header row ("Daily Usage" + today's date pill), then one vertical stem per
/// hour (6am–10pm): grey track is the hour slot, Claude orange is how much of
/// today's peak-hour activity fell in that hour. Each stem carries a percent
/// label over an hour label, mirroring the Grok day columns.
struct ClaudeHourlyUsageChart: View {
    let hourWeights: [Double]

    private let trackHeight: CGFloat = PanelChartStem.height
    private static let firstHour = 6
    private static let lastHour = 22 // 10pm
    private static let stemWidth: CGFloat = PanelChartStem.width
    private static let barCornerRadius: CGFloat = PanelChartStem.cornerRadius

    private var hours: [Int] {
        Array(Self.firstHour...Self.lastHour)
    }

    private var maxWeight: Double {
        hours.map { weight(forHour: $0) }.max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                PanelSectionHeader(title: "Daily Usage")
                Spacer(minLength: 8)
                PanelPill(text: Format.resetDate(Date(), dateFormat: "EEE d MMM"))
            }

            if maxWeight > 0 {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(hours, id: \.self) { hour in
                        hourColumn(hour)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: trackHeight + 36)
            } else {
                Text("No Claude activity yet today.")
                    .font(PanelTypography.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }
        }
    }

    private func hourColumn(_ hour: Int) -> some View {
        let weight = weight(forHour: hour)
        let fraction = maxWeight > 0 ? min(1, weight / maxWeight) : 0
        let fillHeight = max(6, trackHeight * CGFloat(fraction))

        return VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                Color.primary.opacity(0.12)

                if weight > 0 {
                    ConcentricUsageRingView.claudeColor
                        .frame(height: min(trackHeight, fillHeight))
                }
            }
            .frame(width: Self.stemWidth, height: trackHeight)
            .clipShape(RoundedRectangle(cornerRadius: Self.barCornerRadius, style: .continuous))
            .frame(maxWidth: .infinity)
            .help(hourHelp(hour, weight: weight))

            VStack(spacing: 1) {
                Text(weight > 0.5 ? "\(Int(weight.rounded()))%" : " ")
                    .font(PanelTypography.micro)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(Format.hourLabel(for: hour))
                    .font(PanelTypography.micro)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(height: 26)
        }
        .frame(maxWidth: .infinity)
    }

    private func weight(forHour hour: Int) -> Double {
        guard hourWeights.indices.contains(hour) else { return 0 }
        return max(0, hourWeights[hour])
    }

    private func hourHelp(_ hour: Int, weight: Double) -> String {
        guard weight > 0 else { return "" }
        let quota = String(format: "%.2f%% of 5-hour window", weight)
        return "\(Format.hourLabel(for: hour)): \(quota)"
    }
}
