import Foundation
import CoreTransferable

// MARK: - Platform

/// The social platforms SocialTea understands. The app never talks to any of them —
/// these values only describe which official data export a list came from.
enum Platform: String, CaseIterable, Identifiable, Hashable, Sendable {
    case instagram
    case facebook
    case tiktok

    var id: String { rawValue }

    var name: String {
        switch self {
        case .instagram: return "Instagram"
        case .facebook: return "Facebook"
        case .tiktok: return "TikTok"
        }
    }

    /// Generic SF Symbol — never a platform logo.
    var symbol: String {
        switch self {
        case .instagram: return "camera.circle.fill"
        case .facebook: return "person.2.circle.fill"
        case .tiktok: return "music.note.tv.fill"
        }
    }

    /// Facebook friendships are two-way by definition.
    var friendsAreMutual: Bool { self == .facebook }

    var followersNoun: String { friendsAreMutual ? "Friends" : "Followers" }
    var followingNoun: String { friendsAreMutual ? "Friends" : "Following" }

    /// Web profile link. Opening it hands off to the official app or Safari;
    /// SocialTea itself never loads it.
    func profileURL(for person: Person) -> URL? {
        let handle = person.username
        switch self {
        case .instagram:
            return URL(string: "https://www.instagram.com/\(handle.urlPathEscaped)/")
        case .tiktok:
            return URL(string: "https://www.tiktok.com/@\(handle.urlPathEscaped)")
        case .facebook:
            if person.looksLikeHandle {
                return URL(string: "https://www.facebook.com/\(handle.urlPathEscaped)")
            }
            var components = URLComponents(string: "https://www.facebook.com/search/top/")
            components?.queryItems = [URLQueryItem(name: "q", value: person.displayName ?? handle)]
            return components?.url
        }
    }
}

// MARK: - Person

/// One account in a follower/following list. Identity is the normalized key so the
/// same account matches across files regardless of case, "@", or URL form.
struct Person: Identifiable, Hashable, Sendable {
    /// Normalized, lowercased identity key.
    let id: String
    /// Handle as it appeared in the export (or a name, for Facebook).
    let username: String
    let displayName: String?
    /// When the relationship started, if the export says so.
    let date: Date?
    /// Position in the source file (0 = first). Used for "newest imported first".
    let order: Int

    init(username: String, displayName: String? = nil, date: Date? = nil, order: Int = 0) {
        self.username = username
        self.displayName = displayName
        self.date = date
        self.order = order
        self.id = Person.normalizedKey(username)
    }

    /// True when `username` is a handle (no spaces) rather than a full name.
    var looksLikeHandle: Bool { !username.contains(" ") }

    var title: String { looksLikeHandle ? "@\(username)" : username }

    var initial: String {
        let source = displayName ?? username
        guard let first = source.first(where: { $0.isLetter || $0.isNumber }) else { return "?" }
        return String(first).uppercased()
    }

    static func normalizedKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func == (lhs: Person, rhs: Person) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Person: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.username)
    }
}

// MARK: - Snapshot

/// One point-in-time copy of a platform's lists. Lives in memory only.
struct Snapshot: Sendable {
    /// Counts recorded without names (used by the bundled baseline when it ships counts only).
    struct Summary: Sendable, Equatable {
        var followers: Int
        var following: Int
        var notFollowingBack: Int?
    }

    var label: String
    var date: Date?
    var followers: [Person]?
    var following: [Person]?
    var summary: Summary?
    var isBundledBaseline: Bool = false
    var isDemo: Bool = false

    var hasNames: Bool { !(followers ?? []).isEmpty || !(following ?? []).isEmpty }
    var isEmpty: Bool { followers == nil && following == nil && summary == nil }
}

// MARK: - Platform data

/// Everything loaded for one platform this session: an older/baseline snapshot and an
/// optional newer one used for "Unfollowed" and "New followers".
struct PlatformData: Sendable {
    var baseline: Snapshot?
    var newer: Snapshot?

    /// The snapshot that represents "now".
    var current: Snapshot? { newer ?? baseline }
    var isLoaded: Bool { !(current?.isEmpty ?? true) }
    var canCompare: Bool {
        guard let b = baseline, let n = newer else { return false }
        return b.followers != nil && n.followers != nil
    }
}

// MARK: - Relationship views

enum RelationshipView: String, CaseIterable, Identifiable, Sendable {
    case notFollowingBack
    case fans
    case mutuals
    case unfollowed
    case newFollowers
    case goneQuiet

    var id: String { rawValue }

    func title(for platform: Platform) -> String {
        switch self {
        case .notFollowingBack: return "Not following back"
        case .fans: return "Fans"
        case .mutuals: return platform.friendsAreMutual ? "Friends" : "Mutuals"
        case .unfollowed: return platform.friendsAreMutual ? "Unfriended" : "Unfollowed"
        case .newFollowers: return platform.friendsAreMutual ? "New friends" : "New followers"
        case .goneQuiet: return "Gone quiet"
        }
    }

    var symbol: String {
        switch self {
        case .notFollowingBack: return "person.crop.circle.badge.xmark"
        case .fans: return "heart.circle"
        case .mutuals: return "arrow.left.arrow.right.circle"
        case .unfollowed: return "person.crop.circle.badge.minus"
        case .newFollowers: return "person.crop.circle.badge.plus"
        case .goneQuiet: return "moon.zzz"
        }
    }

    /// One plain sentence explaining the view.
    func explanation(for platform: Platform) -> String {
        switch self {
        case .notFollowingBack:
            return platform.friendsAreMutual
                ? "Facebook friends are always two-way, so nobody can be \"not following back\" — this is 0."
                : "You follow them, but they don't follow you."
        case .fans:
            return platform.friendsAreMutual
                ? "Facebook friends are always two-way, so there are no one-way fans — this is 0."
                : "They follow you, but you don't follow them."
        case .mutuals:
            return platform.friendsAreMutual
                ? "Everyone on your Facebook friends list. Friendships are mutual by definition."
                : "You follow each other."
        case .unfollowed:
            return "They were in your older snapshot but are missing from your newer one."
        case .newFollowers:
            return "They're in your newer snapshot but weren't in your older one."
        case .goneQuiet:
            return "They vanished from all of your lists. They may have blocked you, deactivated, or been removed — the app cannot tell which."
        }
    }

    var needsTwoSnapshots: Bool {
        switch self {
        case .unfollowed, .newFollowers, .goneQuiet: return true
        default: return false
        }
    }
}

// MARK: - Helpers

extension String {
    var urlPathEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}
