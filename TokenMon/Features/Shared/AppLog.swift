import Foundation
import os

/// Single source of truth for logging subsystem and User-Agent identity.
/// Replaces the copy-pasted "com.modelmonitor.app" / "TokenMon/1.0" strings.
enum AppLog {
    static let subsystem = "com.modelmonitor.app"
}

enum AppIdentity {
    /// e.g. "TokenMon/1.2.0" — version tracks MARKETING_VERSION automatically.
    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        return "TokenMon/\(version)"
    }
}

extension Logger {
    init(category: String) {
        self.init(subsystem: AppLog.subsystem, category: category)
    }
}
