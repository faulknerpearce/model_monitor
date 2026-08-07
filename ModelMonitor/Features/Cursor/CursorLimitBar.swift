import SwiftUI

/// Limit bar styled like OpenCode/Grok — fill and label show **used** percent.
struct CursorPoolBar: View {
    let pool: CursorPoolUsage

    private static let fillSRGB: [CursorPoolKind: (red: Double, green: Double, blue: Double)] = [
        .total: (0.12, 0.42, 0.28),   // Dark green
        .auto: (0.18, 0.53, 0.38),   // Medium green
        .api: (0.25, 0.65, 0.50)    // Light green
    ]

    private var fill: Color {
        let srgb = Self.fillSRGB[pool.kind] ?? (0.18, 0.53, 0.67)
        return Color(red: srgb.red, green: srgb.green, blue: srgb.blue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(pool.kind.label)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(Int(pool.usedPercent.rounded()))% used")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(PanelTypography.body)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.18))
                    Capsule()
                        .fill(fill)
                        .frame(width: max(0, geo.size.width * CGFloat(pool.usedPercent / 100)))
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())

            if let resetsAt = pool.resetsAt {
                Text("Resets \(Format.resetDate(resetsAt, dateFormat: "EEE dd MMMM h:mma"))")
                    .font(PanelTypography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
