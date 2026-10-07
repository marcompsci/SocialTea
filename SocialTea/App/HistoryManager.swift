import Foundation

/// Persists per-platform follower/following counts across sessions so InsightsView
/// can render a time-series trend chart. Only aggregate numbers — no names — are stored.
@MainActor
@Observable
final class HistoryManager {
    struct SnapshotRecord: Codable, Identifiable {
        let id: UUID
        let date: Date
        let platform: String
        let followers: Int
        let following: Int

        init(platform: String, followers: Int, following: Int) {
            self.id = UUID()
            self.date = Date()
            self.platform = platform
            self.followers = followers
            self.following = following
        }
    }

    private let key = "history.snapshots"
    private let maxPerPlatform = 30
    private(set) var records: [SnapshotRecord] = []

    init() {
        if let data = SyncedPrefs.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SnapshotRecord].self, from: data) {
            records = decoded
        }
    }

    /// Records a follower snapshot for the platform. Skips if one already exists
    /// for today's calendar date (one snapshot per day per platform).
    func record(platform: Platform, followers: Int, following: Int) {
        guard followers > 0 else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let alreadyToday = records.contains {
            $0.platform == platform.rawValue &&
            cal.startOfDay(for: $0.date) == today
        }
        guard !alreadyToday else { return }

        var updated = records
        updated.append(SnapshotRecord(platform: platform.rawValue, followers: followers, following: following))
        records = Platform.allCases.flatMap { p in
            updated.filter { $0.platform == p.rawValue }.suffix(maxPerPlatform)
        }
        if let data = try? JSONEncoder().encode(records) {
            SyncedPrefs.set(data, forKey: key)
        }
    }

    func history(for platform: Platform) -> [SnapshotRecord] {
        records.filter { $0.platform == platform.rawValue }.sorted { $0.date < $1.date }
    }

    func clear() {
        records = []
        SyncedPrefs.removeObject(forKey: key)
    }
}
