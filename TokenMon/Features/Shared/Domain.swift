import Foundation

/// Canonical host matching for provider cookie domains.
enum Domain {
    static func matches(_ domain: String, hosts: [String]) -> Bool {
        let trimmed = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return hosts.contains { host in
            trimmed == host || trimmed.hasSuffix(".\(host)")
        }
    }
}
