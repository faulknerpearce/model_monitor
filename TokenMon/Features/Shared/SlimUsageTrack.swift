import SwiftUI

/// Used-percent track: label left, percent right, 8px fill (matches Grok weekly bar).
struct SlimUsageTrack: View {
    let label: String
    let percent: Double
    var color: Color
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(PanelTypography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(Percent.clamp(percent).rounded()))%")
                    .font(PanelTypography.caption)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.usageRemainingTrack)
                    Capsule()
                        .fill(color)
                        .frame(width: max(0, geo.size.width * CGFloat(Percent.clamp(percent) / 100)))
                }
            }
            .frame(height: 8)

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(PanelTypography.micro)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
