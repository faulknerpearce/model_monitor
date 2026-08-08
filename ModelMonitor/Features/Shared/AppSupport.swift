import Foundation

/// Centralized access to the app's per-user Application Support directory.
///
/// Several subsystems (auth cookie store, history store) each re-implemented
/// creating `Application Support/<app>` with `0700` permissions. Hoisting that
/// here keeps the directory location and hardening consistent in one place.
enum AppSupport {
    /// The app's Application Support directory (created on demand, `0700`).
    /// Defaults to `~/Library/Application Support/ModelMonitor`.
    static func directory(subdirectory: String = "ModelMonitor") -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent(subdirectory, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }
}
