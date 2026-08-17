import Foundation

enum MonitorProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case overview
    case grok
    case cursor
    case opencode

    var id: String { rawValue }

    /// Concrete usage providers in dropdown / menu-bar order (Overview excluded).
    static var usageProviders: [MonitorProvider] { [.grok, .cursor, .opencode] }

    var displayName: String {
        switch self {
        case .overview: return "Overview"
        case .grok: return "Grok"
        case .opencode: return "OpenCode"
        case .cursor: return "Cursor"
        }
    }

    /// Short label in the dropdown provider switcher.
    var switcherLabel: String {
        switch self {
        case .overview: return "All"
        case .grok, .cursor, .opencode: return displayName
        }
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
