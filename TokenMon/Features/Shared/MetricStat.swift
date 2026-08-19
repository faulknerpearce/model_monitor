import SwiftUI

/// A single title + value stat cell (label above a monospaced hero value).
struct MetricStat: View {
    let title: String
    let value: String
    var monospaced: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(PanelTypography.captionMedium)
                .foregroundStyle(.secondary)
            if monospaced {
                Text(value).monospacedDigit()
                    .font(PanelTypography.hero)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(value)
                    .font(PanelTypography.hero)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    }
}

/// A row of `MetricStat` cells separated by vertical dividers.
///
/// Replaces the duplicated `metricColumn` / `valueText` / `verticalDivider`
/// pairs in the provider panels with one shared layout.
struct MetricStatGrid: View {
    let stats: [MetricStat]

    init(_ stats: [MetricStat]) {
        self.stats = stats
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                if index > 0 {
                    Divider()
                        .frame(height: 48)
                        .padding(.horizontal, 14)
                }
                stat
            }
        }
    }
}
