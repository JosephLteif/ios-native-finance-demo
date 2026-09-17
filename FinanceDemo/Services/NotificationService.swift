import Foundation
import UserNotifications

enum NotificationService {
    private static let scheduledPrefix = "pocket-ledger-scheduled-"

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

    static func requestScheduledTransactionNotifications(
        schedules: [ScheduledTransaction]
    ) async -> String {
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

        await refreshScheduledTransactionNotifications(schedules: schedules)
        return "Scheduled-entry reminders are enabled."
    }

    static func refreshScheduledTransactionNotifications(
        schedules: [ScheduledTransaction]
    ) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let existingIDs = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(scheduledPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existingIDs)

        let calendar = Calendar.current
        for schedule in schedules where schedule.isEnabled && schedule.nextRunDate > .now {
            let content = UNMutableNotificationContent()
            content.title = "Pocket Ledger"
            content.body = schedule.note.isEmpty
                ? "\(schedule.kind.displayName) is due."
                : schedule.note
            content.sound = .default
            content.userInfo = ["scheduledTransactionID": schedule.id.uuidString]

            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: schedule.nextRunDate
            )
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: scheduledPrefix + schedule.id.uuidString,
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
            } catch {
                continue
            }
        }
    }
}
