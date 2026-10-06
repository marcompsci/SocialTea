import Foundation
import WidgetKit

// Persists last-known follower counts so the home-screen widget can display them.
// Requires App Groups — see SocialTeaWidget.swift for full setup instructions.
enum WidgetDataCache {
    /// Off by default. Only when the user turns this on are follower counts saved on the
    /// device for the widget and Siri. Turning it off erases them.
    static let optInKey = "widget.optIn"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: optInKey) }
    // Must match the App Group identifier you add in Xcode Signing & Capabilities.
    static let suiteName = "group.com.socialtea"

    struct Entry: Codable {
        var platform: String
        var followers: Int
        var following: Int
        var followBackRatio: Double
        var lastUpdated: Date
    }

    @MainActor
    static func update(from store: SessionStore) {
        guard isEnabled else { return }
        let entries: [Entry] = store.loadedPlatforms.map { platform in
            let stats = store.stats(platform)
            return Entry(
                platform: platform.name,
                followers: stats.followers,
                following: stats.following,
                followBackRatio: stats.followBackRatio,
                lastUpdated: Date()
            )
        }
        save(entries)
    }

    static func save(_ entries: [Entry]) {
        // Fall back to standard if App Groups aren't configured yet (no crash).
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: "widget.entries")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Removes every saved count (used when the user turns the feature off).
    static func clear() {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removeObject(forKey: "widget.entries")
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func load() -> [Entry] {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        guard let data = defaults.data(forKey: "widget.entries"),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }
}
