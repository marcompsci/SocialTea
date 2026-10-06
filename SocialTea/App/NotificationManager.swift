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

    /// Reschedules the reminder with live context data. Call whenever the app moves to the background.
    func updateDigest(streak: Int, queueCount: Int, totalFollowers: Int) {
        guard enabled else { return }
        scheduleReminder(streak: streak, queueCount: queueCount, totalFollowers: totalFollowers)
    }

    private func scheduleReminder(streak: Int = 0, queueCount: Int = 0, totalFollowers: Int = 0) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["socialtea.reminder"])
        let content = UNMutableNotificationContent()
        content.sound = .default

        var parts: [String] = []
        if streak > 1 { parts.append("🔥 \(streak)-day streak") }
        if queueCount > 0 { parts.append("\(queueCount) in your unfollow queue") }

        if !parts.isEmpty {
            content.title = "SocialTea check-in"
            content.body  = parts.joined(separator: " · ")
        } else {
            content.title = "Time for a tea check ☕"
            content.body  = totalFollowers > 0
                ? "You have \(totalFollowers.formatted()) followers. Grab a fresh export to see what's changed."
                : "Grab a fresh export and see what\u{2019}s changed since your last snapshot."
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval.seconds, repeats: true)
        center.add(UNNotificationRequest(identifier: "socialtea.reminder", content: content, trigger: trigger))
    }

    private func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["socialtea.reminder"])
    }
}
