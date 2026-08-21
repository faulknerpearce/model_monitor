import SwiftUI

/// Today's hourly Claude 5-hour-window usage (percentage-point deltas between polls).
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
            if maxWeight > 0 {
                hourBars
            } else {
                Text("No Claude activity yet today.")
                    .font(PanelTypography.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }
        }
    }

    private var hourBars: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(hours, id: \.self) { hour in
                hourColumn(hour)
            }
        }
        .frame(height: trackHeight + 14)
    }

    private func hourColumn(_ hour: Int) -> some View {
        let weight = weight(forHour: hour)
        let fraction = maxWeight > 0 ? min(1, weight / maxWeight) : 0
        let fillHeight = weight > 0 ? max(6, trackHeight * CGFloat(fraction)) : 0
        let showAxis = [Self.firstHour, 9, 12, 15, 18, Self.lastHour].contains(hour)

        return VStack(spacing: 5) {
            ZStack(alignment: .bottom) {
                Color.clear
                    .frame(width: Self.stemWidth, height: trackHeight)

                if weight > 0 {
                    ConcentricUsageRingView.claudeColor
                        .frame(width: Self.stemWidth, height: min(trackHeight, fillHeight))
                        .clipShape(RoundedRectangle(cornerRadius: Self.barCornerRadius, style: .continuous))
                } else {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: Self.stemWidth, height: 2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: trackHeight, alignment: .bottom)
            .help(hourHelp(hour, weight: weight))

            Text(showAxis ? Self.axisLabel(for: hour) : " ")
                .font(PanelTypography.micro)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: 10)
        }
        .frame(maxWidth: .infinity)
    }

    private func weight(forHour hour: Int) -> Double {
        guard hourWeights.indices.contains(hour) else { return 0 }
        return max(0, hourWeights[hour])
    }

    private static func axisLabel(for hour: Int) -> String {
        switch hour {
        case 0, 12: return "12"
        case 13...23: return "\(hour - 12)"
        default: return "\(hour)"
        }
    }

    private func hourHelp(_ hour: Int, weight: Double) -> String {
        guard weight > 0 else { return "" }
        let quota = String(format: "%.2f%% of 5-hour window", weight)
        return "\(Format.hourLabel(for: hour)): \(quota)"
    }
}
