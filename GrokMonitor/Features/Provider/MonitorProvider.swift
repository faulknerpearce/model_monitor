import Foundation

enum MonitorProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case overview
    case grok
    case opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .overview: return "Overview"
        case .grok: return "Grok"
        case .opencode: return "OpenCode"
        }
    }

    /// Whether this mode should refresh Grok usage.
    var pollsGrok: Bool {
        self == .grok || self == .overview
    }

    /// Whether this mode should refresh OpenCode usage.
    var pollsOpenCode: Bool {
        self == .opencode || self == .overview
    }
}
