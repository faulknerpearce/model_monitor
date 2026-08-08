import Combine
import Foundation
import os
import UserNotifications

@MainActor
final class ThresholdNotifier: ObservableObject {
    private let logger = Logger(subsystem: "com.modelmonitor.app", category: "Alerts")
    private var lastNotifiedThreshold: Double?

    func requestAuthorizationIfNeeded() {
        Task { @MainActor [weak self] in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                if !granted {
                    self?.logger.info("User denied notification permission")
                }
            } catch {
                self?.logger.error("Notification auth failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func evaluate(usedPercent: Double, settings: AppSettings) {
        guard settings.thresholdEnabled else { return }
        let threshold = settings.thresholdPercent
        guard usedPercent >= threshold else {
            if let last = lastNotifiedThreshold, usedPercent < last - 5 {
                lastNotifiedThreshold = nil
            }
            return
        }
        if let last = lastNotifiedThreshold, last >= threshold {
            return
        }
        lastNotifiedThreshold = threshold
        send(usedPercent: usedPercent, threshold: threshold)
    }

    private func send(usedPercent: Double, threshold: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Model Monitor Alert"
        content.body = String(
            format: "Weekly SuperGrok usage is at %.0f%% (threshold %.0f%%).",
            usedPercent,
            threshold
        )
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "grok-usage-threshold-\(Int(threshold))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        logger.info("Sent threshold notification at \(usedPercent, privacy: .public)%")
    }
}
