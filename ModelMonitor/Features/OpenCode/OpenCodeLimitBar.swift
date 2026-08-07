import SwiftUI

struct OpenCodeLimitBar: View {
    let window: OpenCodeWindowUsage

    private static let fillSRGB: [OpenCodeWindowKind: (red: Double, green: Double, blue: Double)] = [
        .rolling5h: (1.0, 0.55, 0.0),   // Orange for Zen
        .weekly: (0.58, 0.44, 0.86),     // Purple
        .monthly: (0.45, 0.32, 0.68)     // Darker purple
    ]

    private var fill: Color {
        let srgb = Self.fillSRGB[window.kind] ?? (0.45, 0.45, 0.45)
        return Color(red: srgb.red, green: srgb.green, blue: srgb.blue)
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
                Text(resetLabel(for: resetsAt))
                    .font(PanelTypography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func resetLabel(for date: Date) -> String {
        switch window.kind {
        case .rolling5h:
            return "Resets \(date.formatted(.relative(presentation: .named)))"
        case .weekly:
            return "Resets \(Format.resetDate(date, dateFormat: "EEE h:mma"))"
        case .monthly:
            return "Resets \(Format.resetDate(date, dateFormat: "EEE dd MMMM h:mma"))"
        }
    }
}
