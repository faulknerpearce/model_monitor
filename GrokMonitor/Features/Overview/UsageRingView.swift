import SwiftUI

struct UsageRingView: View {
    let title: String
    let percent: Double?
    let color: Color
    var emptyCaption: String = "—"

    private var displayPercent: Double {
        Percent.clamp(percent ?? 0)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(displayPercent / 100))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.35), value: displayPercent)

                if let percent {
                    Text("\(Int(percent.rounded()))%")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text(emptyCaption)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 88, height: 88)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
