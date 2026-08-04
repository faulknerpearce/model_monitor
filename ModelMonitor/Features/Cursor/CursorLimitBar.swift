import SwiftUI

/// Limit bar styled like OpenCode/Grok — fill and label show **used** percent.
struct CursorPoolBar: View {
    let pool: CursorPoolUsage

    private let fill = ConcentricUsageRingView.cursorColor

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
                Text("Resets \(resetsAt.formatted(.relative(presentation: .named)))")
                    .font(PanelTypography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
