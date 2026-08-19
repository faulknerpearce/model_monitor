import SwiftUI

struct OpenCodeLimitBar: View {
    let window: OpenCodeWindowUsage

    private static let fillSRGB: [OpenCodeWindowKind: SRGB] = [
        .rolling5h: SRGB(red: 1.0, green: 0.55, blue: 0.0),   // Orange for Zen
        .weekly: SRGB(red: 0.58, green: 0.44, blue: 0.86),     // Purple
        .monthly: SRGB(red: 0.45, green: 0.32, blue: 0.68)     // Darker purple
    ]

    private var fill: Color {
        (Self.fillSRGB[window.kind] ?? SRGB(red: 0.45, green: 0.45, blue: 0.45)).color
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
