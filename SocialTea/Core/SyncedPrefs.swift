import Foundation

/// Mirrors every preference write to both UserDefaults and NSUbiquitousKeyValueStore.
/// On read the cloud value wins (most-recently-written device takes precedence);
/// falls back to UserDefaults when the key isn't in iCloud or the user isn't signed in.
enum SyncedPrefs {

    private static var cloud: NSUbiquitousKeyValueStore { .default }

    /// Call once at launch so the store fetches the latest cloud values before
    /// any manager reads its preferences.
    static func synchronize() { cloud.synchronize() }

    // MARK: - Writes (both stores)

    static func set(_ value: Data?, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        cloud.set(value, forKey: key)
    }

    static func set(_ value: Bool, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        cloud.set(value, forKey: key)
    }

    static func set(_ value: String?, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        cloud.set(value, forKey: key)
    }

    static func set(_ value: Int, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        cloud.set(Int64(value), forKey: key)
    }

    static func set(_ value: Double, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        cloud.set(value, forKey: key)
    }

    static func set(_ value: Date?, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        cloud.set(value, forKey: key)
    }

    static func removeObject(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        cloud.removeObject(forKey: key)
    }

    // MARK: - Reads (cloud preferred, UserDefaults fallback)

    static func data(forKey key: String) -> Data? {
        cloud.data(forKey: key) ?? UserDefaults.standard.data(forKey: key)
    }

    static func bool(forKey key: String) -> Bool {
        if cloud.object(forKey: key) != nil { return cloud.bool(forKey: key) }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func string(forKey key: String) -> String? {
        cloud.string(forKey: key) ?? UserDefaults.standard.string(forKey: key)
    }

    static func integer(forKey key: String) -> Int {
        if cloud.object(forKey: key) != nil { return Int(cloud.longLong(forKey: key)) }
        return UserDefaults.standard.integer(forKey: key)
    }

    static func double(forKey key: String) -> Double {
        if cloud.object(forKey: key) != nil { return cloud.double(forKey: key) }
        return UserDefaults.standard.double(forKey: key)
    }

    static func object(forKey key: String) -> Any? {
        cloud.object(forKey: key) ?? UserDefaults.standard.object(forKey: key)
    }
}
