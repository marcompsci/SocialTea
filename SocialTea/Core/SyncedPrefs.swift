import Foundation

/// Small wrapper for app preferences (theme, reminders, goals, opt-in history).
///
/// Local only: values are kept in this phone's UserDefaults and are never mirrored to
/// iCloud or sent anywhere. (The name is kept so existing call sites don't change.)
enum SyncedPrefs {

    private static var store: UserDefaults { .standard }

    /// Kept for source compatibility; there is nothing to sync.
    static func synchronize() {}

    // MARK: - Writes

    static func set(_ value: Data?, forKey key: String) { store.set(value, forKey: key) }
    static func set(_ value: Bool, forKey key: String) { store.set(value, forKey: key) }
    static func set(_ value: String?, forKey key: String) { store.set(value, forKey: key) }
    static func set(_ value: Int, forKey key: String) { store.set(value, forKey: key) }
    static func set(_ value: Double, forKey key: String) { store.set(value, forKey: key) }
    static func set(_ value: Date?, forKey key: String) { store.set(value, forKey: key) }
    static func removeObject(forKey key: String) { store.removeObject(forKey: key) }

    // MARK: - Reads

    static func data(forKey key: String) -> Data? { store.data(forKey: key) }
    static func bool(forKey key: String) -> Bool { store.bool(forKey: key) }
    static func string(forKey key: String) -> String? { store.string(forKey: key) }
    static func integer(forKey key: String) -> Int { store.integer(forKey: key) }
    static func double(forKey key: String) -> Double { store.double(forKey: key) }
    static func object(forKey key: String) -> Any? { store.object(forKey: key) }
}
