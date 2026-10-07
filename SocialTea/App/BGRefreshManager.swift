import BackgroundTasks
import WidgetKit

/// Schedules and handles a periodic BGAppRefreshTask that keeps the widget
/// timeline and Spotlight index fresh between user sessions.
///
/// Manual setup required (once):
///   Xcode → SocialTea target → Info tab → add array key:
///     BGTaskSchedulerPermittedIdentifiers  →  com.socialtea.refresh
enum BGRefreshManager {
    static let identifier = "com.socialtea.refresh"

    /// Register the handler. Must be called before the first scene becomes active
    /// (i.e., in SocialTeaApp.init).
    static func registerHandler() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            WidgetCenter.shared.reloadAllTimelines()
            task.setTaskCompleted(success: true)
            schedule()
        }
    }

    /// Submit (or replace) the next scheduled background-refresh request.
    /// Call from the .background scene-phase handler.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
