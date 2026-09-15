import Foundation
import UserNotifications

enum NotificationService {
    static func scheduleDemoNotification() async -> String {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    return "Notification permission was not granted."
                }
            } catch {
                return "Notification permission failed: \(error.localizedDescription)"
            }
        case .denied:
            return "Notifications are disabled for this app."
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            return "Notification permission has an unknown status."
        }

        let content = UNMutableNotificationContent()
        content.title = "Pocket Ledger"
        content.body = "Pocket Ledger notification works."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        let request = UNNotificationRequest(
            identifier: "finance-demo-test-notification",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            return "Notification scheduled for about 10 seconds from now."
        } catch {
            return "Notification scheduling failed: \(error.localizedDescription)"
        }
    }
}
