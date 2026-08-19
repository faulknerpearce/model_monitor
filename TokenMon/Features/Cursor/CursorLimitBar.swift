import SwiftUI

/// Limit bar styled like OpenCode/Grok — fill and label show **used** percent.
struct CursorPoolBar: View {
    let pool: CursorPoolUsage

    private static let fillSRGB: [CursorPoolKind: SRGB] = [
        .total: SRGB(red: 0.12, green: 0.42, blue: 0.28),   // Dark green
        .auto: SRGB(red: 0.18, green: 0.53, blue: 0.38),   // Medium green
        .api: SRGB(red: 0.25, green: 0.65, blue: 0.50)    // Light green
    ]

    private var fill: Color {
        (Self.fillSRGB[pool.kind] ?? SRGB(red: 0.18, green: 0.53, blue: 0.67)).color
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
