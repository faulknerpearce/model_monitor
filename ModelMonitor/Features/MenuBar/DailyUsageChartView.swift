import SwiftUI

/// Settings → Usage style “Daily use” bar chart for the **billing period** week.
///
/// Each day’s track is an equal share of the weekly pool (`100/7`).
/// Bars use a uniform fill — no “today” highlight and no mid-period split bars.
struct DailyUsageChartView: View {
    let week: DailyUsageWeek
    var onPreviousWeek: (() -> Void)?
    var onNextWeek: (() -> Void)?
    var canGoNext: Bool = true

    private let trackHeight: CGFloat = 112
    private let barWidth: CGFloat = 40
    private static let barCornerRadius: CGFloat = 4
    private static let columnSpacing: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelSectionHeader(title: "Daily Usage")

            HStack(spacing: 8) {
                weekNavButton(systemName: "chevron.left", action: onPreviousWeek)

                Text(week.rangeLabel)
                    .font(PanelTypography.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)

                weekNavButton(
                    systemName: "chevron.right",
                    action: onNextWeek,
                    disabled: !canGoNext
                )
            }

            HStack(alignment: .bottom, spacing: Self.columnSpacing) {
                ForEach(week.displayDays) { day in
                    dayColumn(day)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: trackHeight + 48)

            if week.isEstimated || !week.hasDailyData {
                Text("Daily bars only show changes between samples. Week-to-date totals are above.")
                    .font(PanelTypography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func dayColumn(_ day: DailyUsageDay) -> some View {
        VStack(spacing: 4) {
            Text(day.totalPercent > 0.5 ? "\(Int(day.totalPercent.rounded()))%" : " ")
                .font(PanelTypography.micro)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(height: 12)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Self.barCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: barWidth, height: trackHeight)

                let fillHeight = trackHeight * CGFloat(Self.fillFraction(forDayUsage: day.totalPercent))

                RoundedRectangle(cornerRadius: Self.barCornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: barWidth, height: fillHeight)
            }
            .frame(width: barWidth, height: trackHeight, alignment: .bottom)

            VStack(spacing: 1) {
                Text(day.weekdaySymbol)
                    .font(PanelTypography.micro)
                    .foregroundStyle(Color.secondary)
                Text(day.dayOfMonth)
                    .font(PanelTypography.micro)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary.opacity(0.85))
            }
        }
        .frame(width: barWidth)
        .help(
            day.totalPercent > 0.05
                ? String(format: "%.0f%% of weekly pool", day.totalPercent)
                : ""
        )
    }

    private func weekNavButton(
        systemName: String,
        action: (() -> Void)?,
        disabled: Bool = false
    ) -> some View {
        Button {
            action?()
        } label: {
            Image(systemName: systemName)
                .font(PanelTypography.captionSemibold)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary.opacity(0.35) : Color.secondary)
        .disabled(disabled)
    }

    /// Maps weekly-pool percent into track height using the equal daily cap (`100/7`).
    static func fillFraction(forDayUsage percent: Double) -> Double {
        DailyUsageBuilder.fillFraction(forDayUsage: percent)
    }
}

#if DEBUG
#Preview {
    DailyUsageChartView(week: DailyUsageBuilder.preview())
        .padding()
        .frame(width: 340)
}
#endif
