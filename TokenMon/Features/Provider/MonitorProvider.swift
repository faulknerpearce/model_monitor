import Foundation

enum MonitorProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case overview
    case grok
    case cursor
    case opencode
    case claude
    case chatgpt

    var id: String { rawValue }

    /// Concrete usage providers in dropdown / menu-bar order (Overview excluded).
    static var usageProviders: [MonitorProvider] { [.grok, .cursor, .opencode, .claude, .chatgpt] }

    var displayName: String {
        switch self {
        case .overview: return "Overview"
        case .grok: return "Grok"
        case .opencode: return "OpenCode"
        case .cursor: return "Cursor"
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        }
    }

    /// Short label in the dropdown provider switcher.
    var switcherLabel: String {
        switch self {
        case .overview: return "All"
        case .grok, .cursor, .opencode, .claude, .chatgpt: return displayName
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

    /// Whether this mode should refresh Claude usage.
    var pollsClaude: Bool {
        self == .claude || self == .overview
    }

    /// Whether this mode should refresh ChatGPT/Codex usage.
    var pollsChatGPT: Bool {
        self == .chatgpt || self == .overview
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
        case .claude:
            return URL(string: "https://claude.ai/settings/usage")
        case .chatgpt:
            return URL(string: "https://chatgpt.com/codex")
        }
    }
}
