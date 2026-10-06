import Foundation

// MARK: - Bundled baseline snapshot

/// The owner's own baseline snapshot, shipped read-only inside the app bundle
/// (`BaselineSnapshot.json`) with explicit consent. It is never written to; importing
/// replaces it for the session, and "Start over" restores it.
///
/// The file can hold counts only, or full username lists. When lists are present they
/// win, so every number stays consistent with the names behind it.
struct BaselineFile: Codable, Sendable {
    struct Entry: Codable, Sendable {
        var followers: Int
        var following: Int
        var notFollowingBack: Int?
        var followerUsernames: [String]?
        var followingUsernames: [String]?
    }

    var label: String
    var date: String
    var platforms: [String: Entry]

    static func load(from data: Data) -> [Platform: Snapshot] {
        guard let file = try? JSONDecoder().decode(BaselineFile.self, from: data) else { return [:] }
        let date = ImportParser.parseDate(file.date)
        var result: [Platform: Snapshot] = [:]
        for (key, entry) in file.platforms {
            guard let platform = Platform(rawValue: key.lowercased()) else { continue }
            let followers = entry.followerUsernames.flatMap(Self.people)
            var following = entry.followingUsernames.flatMap(Self.people)
            if platform.friendsAreMutual, following == nil { following = followers }
            let hasLists = followers != nil
            result[platform] = Snapshot(
                label: file.label,
                date: date,
                followers: hasLists ? followers : nil,
                following: hasLists ? following : nil,
                summary: Snapshot.Summary(followers: entry.followers,
                                          following: entry.following,
                                          notFollowingBack: platform.friendsAreMutual ? 0 : entry.notFollowingBack),
                isBundledBaseline: true
            )
        }
        return result
    }

    private static func people(_ names: [String]) -> [Person]? {
        let list = ImportParser.dedupe(names.compactMap(ImportParser.cleanUsername).map { Person(username: $0) })
        return list.isEmpty ? nil : list
    }
}

// MARK: - Demo data

/// Deterministic, obviously fake accounts so every screen can be explored with zero imports.
enum DemoData {
    private static let first = ["sunny", "pixel", "mango", "neon", "river", "cosmo", "lofi", "maple", "echo", "nova",
                                "taco", "blaze", "coral", "drift", "fable", "gizmo", "honey", "indigo", "jade", "kiwi"]
    private static let second = ["skates", "bakes", "codes", "films", "draws", "lifts", "travels", "sings", "reads", "surfs"]
    private static let realNames = ["Avery Stone", "Jordan Lee", "Riley Park", "Casey Moore", "Morgan Diaz",
                                    "Quinn Patel", "Sky Rivera", "Drew Kim", "Rowan Ali", "Jamie Fox",
                                    "Taylor Brooks", "Reese Chen", "Parker Nguyen", "Emery Cole", "Hayden Cruz"]

    static func handle(_ i: Int) -> String {
        let a = first[i % first.count]
        let b = second[(i / first.count) % second.count]
        return "demo.\(a)_\(b)"
    }

    private static func people(_ indices: [Int], displayNames: Bool = false) -> [Person] {
        let base = Date(timeIntervalSince1970: 1_756_684_800) // Sep 1, 2025
        return indices.enumerated().map { pos, i in
            let display = displayNames ? "\(realNames[i % realNames.count]) \(i)" : nil
            return Person(username: handle(i), displayName: display,
                          date: base.addingTimeInterval(Double(i) * 86_400), order: pos)
        }
    }

    static func data(for platform: Platform) -> PlatformData {
        switch platform {
        case .facebook:
            let older = Array(0..<30)
            let newer = Array(2..<30) + [40, 41, 42]
            let o = people(older.reversed(), displayNames: true)
            let n = people(newer.reversed(), displayNames: true)
            return PlatformData(
                baseline: Snapshot(label: "Demo · older", date: nil, followers: o, following: o, isDemo: true),
                newer: Snapshot(label: "Demo · newer", date: nil, followers: n, following: n, isDemo: true))
        case .instagram, .tiktok:
            let offset = platform == .tiktok ? 7 : 0
            // Older snapshot
            let oFollowers = Array((0..<60).map { $0 + offset })
            let oFollowing = Array((20..<50).map { $0 + offset }) + Array((100..<118).map { $0 + offset })
            // Newer snapshot: 4 unfollowed you (0–3), 6 new followers (60–65),
            // 2 mutuals vanished from both lists (20, 21) → "gone quiet".
            let nFollowers = Array((4..<66).map { $0 + offset }).filter { $0 != 20 + offset && $0 != 21 + offset }
            let nFollowing = oFollowing.filter { $0 != 20 + offset && $0 != 21 + offset } + [60 + offset, 61 + offset]
            return PlatformData(
                baseline: Snapshot(label: "Demo · older", date: nil,
                                   followers: people(oFollowers.reversed()), following: people(oFollowing.reversed()),
                                   isDemo: true),
                newer: Snapshot(label: "Demo · newer", date: nil,
                                followers: people(nFollowers.reversed()), following: people(nFollowing.reversed()),
                                isDemo: true))
        }
    }
}
