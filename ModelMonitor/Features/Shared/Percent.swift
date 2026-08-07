import CoreGraphics
import Foundation

/// Percentage clamping used by renderers and model math.
enum Percent {
    static func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    static func clamp(_ value: CGFloat) -> CGFloat {
        min(100, max(0, value))
    }
}
