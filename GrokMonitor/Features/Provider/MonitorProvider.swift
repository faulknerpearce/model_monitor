import Foundation

enum MonitorProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case grok
    case opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grok: return "Grok"
        case .opencode: return "OpenCode"
        }
    }
}
