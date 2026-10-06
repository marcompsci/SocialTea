import Foundation
import UserNotifications

@MainActor
@Observable
final class NotificationManager {
    enum ReminderInterval: String, CaseIterable, Identifiable {
        case daily      = "Daily"
        case threeDays  = "Every 3 days"
        case weekly     = "Weekly"

        var id: String { rawValue }

        var seconds: TimeInterval {
            switch self {
            case .daily:     return 86_400
            case .threeDays: return 259_200
            case .weekly:    return 604_800
            }
        }
    }

    var enabled: Bool = false
    var interval: ReminderInterval = .weekly

    init() {
        enabled  = UserDefaults.standard.bool(forKey: "notif.enabled")
        interval = ReminderInterval(rawValue: UserDefaults.standard.string(forKey: "notif.interval") ?? "") ?? .weekly
    }

    func requestAndEnable() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var granted = settings.authorizationStatus == .authorized
        if settings.authorizationStatus == .notDetermined {
            granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        guard granted else { return }
        setEnabled(true)
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: "notif.enabled")
        on ? scheduleReminder() : cancelReminder()
    }

    func updateInterval(_ newInterval: ReminderInterval) {
        interval = newInterval
        UserDefaults.standard.set(newInterval.rawValue, forKey: "notif.interval")
        if enabled { scheduleReminder() }
    }

    private func scheduleReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["socialtea.reminder"])
        let content = UNMutableNotificationContent()
        content.title = "Time for a tea check ☕"
        content.body  = "Grab a fresh export and see what\u{2019}s changed since your last snapshot."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval.seconds, repeats: true)
        center.add(UNNotificationRequest(identifier: "socialtea.reminder", content: content, trigger: trigger))
    }

    private func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["socialtea.reminder"])
    }
}
