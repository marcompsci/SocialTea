import Foundation

/// Optional, off-by-default "Remember last snapshot".
///
/// When the user turns it on, the usernames from their latest imported snapshot (per
/// platform) are written to one file on this phone so the next export can be compared
/// against it — that's what makes Unfollowed / New followers / Gone quiet work across days.
///
/// What is kept: usernames (and display names when the export has them), the snapshot date,
/// and which platform it came from. Nothing else.
/// Where: the app's private Application Support folder, encrypted while the phone is locked
/// (complete file protection) and excluded from iCloud/iTunes backups. It is never sent anywhere.
/// Turning the setting off, Start over, or Clear everything deletes the file immediately.
struct SnapshotMemory {
    static let optInKey = "snapshotMemory.optIn"
    static let shared = SnapshotMemory()

    let directory: URL
    let defaults: UserDefaults

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.directory = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.defaults = defaults
    }

    /// Exact wording shown under the Settings toggle (also used in the privacy policy).
    static let settingsFooter = "Off by default. When on, the usernames from your latest import are saved on this phone \u{2014} and only on this phone \u{2014} so next time you can import just your new export and see who unfollowed you. They are never uploaded or sent anywhere, and are left out of backups. Turn it off to erase them right away."

    var fileURL: URL { directory.appendingPathComponent("RememberedSnapshot.json") }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.optInKey) }
        nonmutating set {
            defaults.set(newValue, forKey: Self.optInKey)
            if !newValue { erase() }
        }
    }

    var hasSavedSnapshot: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    // MARK: File format

    struct StoredPerson: Codable, Equatable {
        var u: String
        var n: String?
    }

    struct StoredSnapshot: Codable {
        var platform: String
        var date: Date
        var followers: [StoredPerson]?
        var following: [StoredPerson]?
    }

    struct File: Codable {
        var version = 1
        var snapshots: [StoredSnapshot]
    }

    // MARK: Save / load / erase

    /// Saves the current real (imported, named) snapshot for each platform.
    /// Demo data and the counts-only bundled baseline are never saved.
    /// Does nothing unless the user turned the setting on.
    @discardableResult
    func save(_ data: [Platform: PlatformData]) -> Bool {
        guard isEnabled else { return false }
        var stored: [StoredSnapshot] = []
        for platform in Platform.allCases {
            let pd = data[platform] ?? PlatformData()
            let real = [pd.newer, pd.baseline].compactMap { $0 }
                .filter { !$0.isDemo && !$0.isBundledBaseline && $0.hasNames }
            guard !real.isEmpty else { continue }
            // Newest list of each kind wins; an older list fills in one the newer import lacks.
            let followers = real.lazy.compactMap(\.followers).first
            let following = real.lazy.compactMap(\.following).first
            stored.append(StoredSnapshot(
                platform: platform.rawValue,
                date: real[0].date ?? Date(),
                followers: followers.map(Self.encode),
                following: following.map(Self.encode)))
        }
        guard !stored.isEmpty else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bytes = try JSONEncoder().encode(File(snapshots: stored))
            #if os(iOS)
            try bytes.write(to: fileURL, options: [.atomic, .completeFileProtection])
            #else
            try bytes.write(to: fileURL, options: [.atomic])
            #endif
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }

    /// Remembered snapshots keyed by platform. Empty when the setting is off.
    func load() -> [Platform: Snapshot] {
        guard isEnabled,
              let bytes = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: bytes) else { return [:] }
        var result: [Platform: Snapshot] = [:]
        for s in file.snapshots {
            guard let platform = Platform(rawValue: s.platform) else { continue }
            var snap = Snapshot(
                label: "Remembered · " + s.date.formatted(date: .abbreviated, time: .omitted),
                date: s.date,
                followers: s.followers.map(Self.decode),
                following: s.following.map(Self.decode))
            snap.isRemembered = true
            result[platform] = snap
        }
        return result
    }

    func erase() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func encode(_ people: [Person]) -> [StoredPerson] {
        people.map { StoredPerson(u: $0.username, n: $0.displayName) }
    }

    private static func decode(_ people: [StoredPerson]) -> [Person] {
        people.enumerated().map { Person(username: $1.u, displayName: $1.n, order: $0) }
    }
}
