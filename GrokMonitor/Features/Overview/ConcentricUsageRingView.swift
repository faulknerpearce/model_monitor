import SwiftUI

/// Fitness-style concentric rings with a right-side usage legend.
struct ConcentricUsageRingView: View {
    let grokPercent: Double?
    let grokRemainingPercent: Double?
    let openCodePercent: Double?
    var openCodeWeekCostUSD: Double? = nil

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
                legendRow(
                    title: "Grok",
                    value: percentText(grokPercent),
                    detail: grokDetail,
                    color: Self.grokColor
                )
                Spacer(minLength: 8)
                legendRow(
                    title: "OpenCode",
                    value: percentText(openCodePercent),
                    detail: openCodeDetail,
                    color: Self.openCodeColor
                )
            }
            .frame(height: size)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var grokDetail: String {
        if let remaining = grokRemainingPercent {
            return "\(Int(remaining.rounded()))% remaining"
        }
        guard let grokPercent else { return "Weekly pool" }
        return "\(Int(max(0, 100 - grokPercent).rounded()))% remaining"
    }

    private var openCodeDetail: String {
        if let cost = openCodeWeekCostUSD, cost > 0 {
            return "\(Self.currency(cost)) this week"
        }
        return "Weekly Go limit"
    }

    private func legendRow(title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
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

    private static func currency(_ value: Double) -> String {
        if value >= 10 { return String(format: "$%.0f", value) }
        if value >= 1 { return String(format: "$%.1f", value) }
        return String(format: "$%.2f", value)
    }
}
