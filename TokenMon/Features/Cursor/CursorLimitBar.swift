import SwiftUI

/// Used-percent track for a Cursor pool (Total / Auto / API).
struct CursorPoolBar: View {
    let pool: CursorPoolUsage

    private var fill: Color {
        switch pool.kind {
        case .total, .auto: return ConcentricUsageRingView.cursorColor
        case .api: return SRGB(red: 0.25, green: 0.65, blue: 0.50).color
        }
    }

    var body: some View {
        SlimUsageTrack(
            label: pool.kind.label,
            percent: pool.usedPercent,
            color: fill,
            caption: pool.resetsAt.map { "Resets \(Format.resetDate($0, dateFormat: "EEE dd MMMM h:mma"))" }
        )
    }
}
