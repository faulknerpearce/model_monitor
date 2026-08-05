import Foundation

enum MonitorProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case overview
    case grok
    case cursor
    case opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .overview: return "Overview"
        case .grok: return "Grok"
        case .opencode: return "OpenCode"
        case .cursor: return "Cursor"
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

    /// Whether this mode should refresh Cursor usage.
    var pollsCursor: Bool {
        self == .cursor || self == .overview
    }

    /// Public dashboard / console URL for “Visit website”.
    var websiteURL: URL? {
        switch self {
        case .overview:
            return nil
        case .grok:
            return URL(string: "https://grok.com/?_s=usage")
        case .opencode:
            return URL(string: "https://opencode.ai")
        case .cursor:
            return URL(string: "https://cursor.com/dashboard/usage")
        }
    }
}
