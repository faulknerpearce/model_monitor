import SwiftUI

/// Fitness-style concentric rings with a right-side usage legend.
/// Outer → inner: Grok, Cursor, OpenCode.
struct ConcentricUsageRingView: View {
    let grokPercent: Double?
    let openCodePercent: Double?
    let cursorPercent: Double?

    static let grokColor = SRGB(red: 0.11, green: 0.38, blue: 0.82).color
    static let openCodeColor = SRGB(red: 0.58, green: 0.44, blue: 0.86).color  // Purple
    static let cursorColor = SRGB(red: 0.18, green: 0.53, blue: 0.38).color   // Medium green

    private let size: CGFloat = 118
    /// Identical stroke width on every ring.
    private let lineWidth: CGFloat = 13
    /// Clear space between adjacent stroke edges (even for all pairs).
    private let ringGap: CGFloat = 5

    /// Center-to-center radial step: half outer stroke + gap + half next stroke.
    private var pitch: CGFloat { lineWidth + ringGap }

    private var middleDiameter: CGFloat { size - 2 * pitch }
    private var innerDiameter: CGFloat { size - 4 * pitch }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                ring(
                    percent: grokPercent,
                    color: Self.grokColor,
                    diameter: size
                )
                ring(
                    percent: cursorPercent,
                    color: Self.cursorColor,
                    diameter: middleDiameter
                )
                ring(
                    percent: openCodePercent,
                    color: Self.openCodeColor,
                    diameter: innerDiameter
                )
            }
            .frame(width: size, height: size)

            Spacer(minLength: 16)

            VStack(alignment: .leading, spacing: 0) {
                legendRow(title: "Grok", value: percentText(grokPercent), color: Self.grokColor)
                Spacer(minLength: 6)
                legendRow(title: "Cursor", value: percentText(cursorPercent), color: Self.cursorColor)
                Spacer(minLength: 6)
                legendRow(title: "OpenCode", value: percentText(openCodePercent), color: Self.openCodeColor)
            }
            .frame(height: size)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func legendRow(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(PanelTypography.captionSemibold)
                .foregroundStyle(.primary)
            Text(value)
                .font(PanelTypography.bodySemibold)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private func ring(percent: Double?, color: Color, diameter: CGFloat) -> some View {
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
