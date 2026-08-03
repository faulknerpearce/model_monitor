import SwiftUI

/// Fitness-style concentric rings with a right-side usage legend.
struct ConcentricUsageRingView: View {
    let grokPercent: Double?
    let openCodePercent: Double?

    static let grokColor = Color(red: 0.11, green: 0.38, blue: 0.82)
    static let openCodeColor = Color(red: 0.90, green: 0.45, blue: 0.20)

    private let size: CGFloat = 96
    private let outerLine: CGFloat = 11
    private let innerLine: CGFloat = 9
    private let ringGap: CGFloat = 5

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                ring(
                    percent: grokPercent,
                    color: Self.grokColor,
                    lineWidth: outerLine,
                    diameter: size
                )
                ring(
                    percent: openCodePercent,
                    color: Self.openCodeColor,
                    lineWidth: innerLine,
                    diameter: size - (outerLine + innerLine + ringGap)
                )
            }
            .frame(width: size, height: size)

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 0) {
                legendRow(title: "Grok", value: percentText(grokPercent), color: Self.grokColor)
                Spacer(minLength: 10)
                legendRow(title: "OpenCode", value: percentText(openCodePercent), color: Self.openCodeColor)
            }
            .frame(height: size)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func legendRow(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(PanelTypography.bodySemibold)
                .foregroundStyle(.primary)
            Text(value)
                .font(PanelTypography.hero)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private func ring(percent: Double?, color: Color, lineWidth: CGFloat, diameter: CGFloat) -> some View {
        let trimmed = Percent.clamp(percent ?? 0) / 100
        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(trimmed))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.35), value: trimmed)
        }
        .frame(width: diameter, height: diameter)
    }

    private func percentText(_ percent: Double?) -> String {
        if let percent {
            return "\(Int(percent.rounded()))%"
        }
        return "—"
    }
}
