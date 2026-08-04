import SwiftUI

struct OpenCodeLimitBar: View {
    let window: OpenCodeWindowUsage

    private static let fillSRGB: [OpenCodeWindowKind: (red: Double, green: Double, blue: Double)] = [
        .rolling5h: (0.90, 0.45, 0.20),
        .weekly: (0.55, 0.78, 1.0),
        .monthly: (0.40, 0.55, 0.82)
    ]

    private var fill: Color {
        let c = Self.fillSRGB[window.kind] ?? (0.45, 0.45, 0.45)
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(window.kind.label)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(Int(window.usedPercent.rounded()))% used")
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
                        .frame(width: max(0, geo.size.width * CGFloat(window.usedPercent / 100)))
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())

            if let resetsAt = window.resetsAt {
                Text("Resets \(resetsAt.formatted(.relative(presentation: .named)))")
                    .font(PanelTypography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
