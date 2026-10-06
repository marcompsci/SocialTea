import Foundation
import Observation

/// Stores per-platform follower goals and tracks the user's daily check-in streak.
/// All data lives in UserDefaults — no personal information is written.
@MainActor
@Observable
final class GoalManager {
    private enum Key {
        static let goals       = "goals.targets"      // [Platform.rawValue: Int]
        static let lastCheckIn = "goals.lastCheckIn"  // Date
        static let streak      = "goals.streak"       // Int
    }

    private(set) var goals: [String: Int]
    private(set) var lastCheckInDate: Date?
    private(set) var streakDays: Int

    init() {
        if let data = UserDefaults.standard.data(forKey: Key.goals),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            goals = decoded
        } else {
            goals = [:]
        }
        lastCheckInDate = UserDefaults.standard.object(forKey: Key.lastCheckIn) as? Date
        streakDays      = UserDefaults.standard.integer(forKey: Key.streak)
    }

    // MARK: - Goals

    func setGoal(_ count: Int, for platform: Platform) {
        if count <= 0 { goals.removeValue(forKey: platform.rawValue) }
        else          { goals[platform.rawValue] = count }
        if let data = try? JSONEncoder().encode(goals) {
            UserDefaults.standard.set(data, forKey: Key.goals)
        }
    }

    func goal(for platform: Platform) -> Int? { goals[platform.rawValue] }

    func progress(followers: Int, for platform: Platform) -> Double? {
        guard let target = goal(for: platform), target > 0 else { return nil }
        return min(Double(followers) / Double(target), 1.0)
    }

    // MARK: - Check-in streak

    /// Call whenever new data is successfully imported.
    func recordCheckIn() {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())

        if let last = lastCheckInDate {
            let lastDay = cal.startOfDay(for: last)
            if lastDay == today { return }
            let diff = cal.dateComponents([.day], from: lastDay, to: today).day ?? 0
            streakDays = (diff == 1) ? streakDays + 1 : 1
        } else {
            streakDays = 1
        }

        lastCheckInDate = Date()
        UserDefaults.standard.set(lastCheckInDate, forKey: Key.lastCheckIn)
        UserDefaults.standard.set(streakDays, forKey: Key.streak)
    }

    var daysSinceCheckIn: Int? {
        guard let date = lastCheckInDate else { return nil }
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day
    }
}
