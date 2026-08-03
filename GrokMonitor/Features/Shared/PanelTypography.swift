import SwiftUI

/// Shared type scale for menu-panel surfaces (Overview / Grok / OpenCode).
enum PanelTypography {
    /// Panel and major section titles.
    static let title = Font.system(size: 13, weight: .semibold)
    /// Subsection labels (e.g. “Usage rings”, “Hourly use”).
    static let section = Font.system(size: 12, weight: .semibold)
    /// Primary body copy and list rows.
    static let body = Font.system(size: 12)
    static let bodySemibold = Font.system(size: 12, weight: .semibold)
    static let bodyDigit = Font.system(size: 12, weight: .semibold).monospacedDigit()
    /// Secondary captions, tags, resets, source labels.
    static let caption = Font.system(size: 11)
    static let captionMedium = Font.system(size: 11, weight: .medium)
    static let captionSemibold = Font.system(size: 11, weight: .semibold)
    /// Chart axis / dense tertiary marks.
    static let micro = Font.system(size: 10)
    /// Large metric values (%, $, token totals).
    static let hero = Font.system(size: 16, weight: .bold, design: .rounded)
}
