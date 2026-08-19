import SwiftUI

/// Quiet label-above-value cell for the 2×2 stats sheet.
struct MetricStat: View {
    let title: String
    let value: String
    var monospaced: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(PanelTypography.metricLabel)
                .foregroundStyle(.tertiary)
            Group {
                if monospaced {
                    Text(value).monospacedDigit()
                } else {
                    Text(value)
                }
            }
            .font(PanelTypography.metricValue)
            .tracking(-0.4)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Unboxed 2×2 type sheet with a full-height / full-width hairline cross.
struct MetricStatGrid: View {
    let stats: [MetricStat]

    init(_ stats: [MetricStat]) {
        self.stats = stats
    }

    var body: some View {
        let top = Array(stats.prefix(2))
        let bottom = Array(stats.dropFirst(2).prefix(2))
        ZStack {
            VStack(spacing: 0) {
                row(top)
                row(bottom)
            }
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1)
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
        }
    }

    private func row(_ cells: [MetricStat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                cell
            }
        }
    }
}
