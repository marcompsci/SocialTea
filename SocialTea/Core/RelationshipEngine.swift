import Foundation

/// The result of one relationship view: either a list of people, or a count with no
/// names (when the snapshot was recorded as counts only), or "needs a second snapshot".
struct ViewResult: Sendable {
    enum Availability: Sendable, Equatable {
        case ready
        case countsOnly
        case needsSecondSnapshot
        case needsFollowingList
        case noData
    }

    var people: [Person]
    var count: Int
    var availability: Availability

    static let noData = ViewResult(people: [], count: 0, availability: .noData)
}

/// Pure set logic for every relationship view. No I/O, no state.
enum RelationshipEngine {

    // MARK: Primitive set operations (exact spec)

    /// In `following` but NOT in `followers`.
    static func notFollowingBack(followers: [Person], following: [Person]) -> [Person] {
        let followerIDs = Set(followers.map(\.id))
        return following.filter { !followerIDs.contains($0.id) }
    }

    /// In `followers` but NOT in `following`.
    static func fans(followers: [Person], following: [Person]) -> [Person] {
        let followingIDs = Set(following.map(\.id))
        return followers.filter { !followingIDs.contains($0.id) }
    }

    /// In both.
    static func mutuals(followers: [Person], following: [Person]) -> [Person] {
        let followingIDs = Set(following.map(\.id))
        return followers.filter { followingIDs.contains($0.id) }
    }

    /// In older followers but NOT in newer followers.
    static func unfollowed(olderFollowers: [Person], newerFollowers: [Person]) -> [Person] {
        let newerIDs = Set(newerFollowers.map(\.id))
        return olderFollowers.filter { !newerIDs.contains($0.id) }
    }

    /// In newer followers but NOT in older followers.
    static func newFollowers(olderFollowers: [Person], newerFollowers: [Person]) -> [Person] {
        let olderIDs = Set(olderFollowers.map(\.id))
        return newerFollowers.filter { !olderIDs.contains($0.id) }
    }

    /// HEURISTIC ONLY. Accounts that were connected to you in BOTH directions before
    /// (they followed you and you followed them) and are now missing from BOTH lists.
    /// A block removes both follows, but so do deactivation, deletion, or a mutual
    /// unfollow — the app cannot tell which, and must always say so.
    static func goneQuiet(older: Snapshot, newer: Snapshot) -> [Person] {
        guard let of = older.followers, let og = older.following,
              let nf = newer.followers, let ng = newer.following else { return [] }
        let stillThere = Set(nf.map(\.id)).union(ng.map(\.id))
        return mutuals(followers: of, following: og).filter { !stillThere.contains($0.id) }
    }

    // MARK: View dispatcher

    static func result(_ view: RelationshipView, platform: Platform, data: PlatformData) -> ViewResult {
        guard let current = data.current, !current.isEmpty else { return .noData }

        // Facebook: friends are mutual by definition.
        if platform.friendsAreMutual {
            switch view {
            case .notFollowingBack, .fans:
                return ViewResult(people: [], count: 0, availability: .ready)
            case .mutuals:
                return listOrCount(current.followers, countFallback: current.summary?.followers)
            default:
                break
            }
        }

        switch view {
        case .notFollowingBack, .fans, .mutuals:
            if let followers = current.followers, let following = current.following {
                let list: [Person]
                switch view {
                case .notFollowingBack: list = notFollowingBack(followers: followers, following: following)
                case .fans: list = fans(followers: followers, following: following)
                default: list = mutuals(followers: followers, following: following)
                }
                return ViewResult(people: list, count: list.count, availability: .ready)
            }
            if let summary = current.summary, current.followers == nil {
                return ViewResult(people: [], count: summaryCount(view, summary) ?? 0, availability: .countsOnly)
            }
            return ViewResult(people: [], count: 0, availability: .needsFollowingList)

        case .unfollowed, .newFollowers:
            guard data.canCompare, let older = data.baseline?.followers, let newer = data.newer?.followers else {
                return ViewResult(people: [], count: 0, availability: .needsSecondSnapshot)
            }
            let list = view == .unfollowed
                ? unfollowed(olderFollowers: older, newerFollowers: newer)
                : newFollowers(olderFollowers: older, newerFollowers: newer)
            return ViewResult(people: list, count: list.count, availability: .ready)

        case .goneQuiet:
            guard data.canCompare, let older = data.baseline, let newer = data.newer else {
                return ViewResult(people: [], count: 0, availability: .needsSecondSnapshot)
            }
            if platform.friendsAreMutual {
                // For friends, vanishing from the friends list is the only signal.
                let list = unfollowed(olderFollowers: older.followers ?? [], newerFollowers: newer.followers ?? [])
                return ViewResult(people: list, count: list.count, availability: .ready)
            }
            guard older.following != nil, newer.following != nil else {
                return ViewResult(people: [], count: 0, availability: .needsFollowingList)
            }
            let list = goneQuiet(older: older, newer: newer)
            return ViewResult(people: list, count: list.count, availability: .ready)
        }
    }

    private static func listOrCount(_ list: [Person]?, countFallback: Int?) -> ViewResult {
        if let list { return ViewResult(people: list, count: list.count, availability: .ready) }
        return ViewResult(people: [], count: countFallback ?? 0, availability: .countsOnly)
    }

    /// Counts derivable from a counts-only summary.
    static func summaryCount(_ view: RelationshipView, _ s: Snapshot.Summary) -> Int? {
        guard let nfb = s.notFollowingBack else { return nil }
        let mutual = max(0, s.following - nfb)
        switch view {
        case .notFollowingBack: return nfb
        case .mutuals: return mutual
        case .fans: return max(0, s.followers - mutual)
        default: return nil
        }
    }

    // MARK: Headline stats

    struct Stats: Sendable, Equatable {
        var followers: Int
        var following: Int
        var notFollowingBack: Int
        var mutuals: Int

        /// Mutuals ÷ following, 0…1.
        var followBackRatio: Double {
            guard following > 0 else { return 0 }
            return min(1, Double(mutuals) / Double(following))
        }

        static let zero = Stats(followers: 0, following: 0, notFollowingBack: 0, mutuals: 0)
    }

    static func stats(platform: Platform, data: PlatformData) -> Stats {
        guard let current = data.current, !current.isEmpty else { return .zero }
        if platform.friendsAreMutual {
            let friends = current.followers?.count ?? current.summary?.followers ?? 0
            return Stats(followers: friends, following: friends, notFollowingBack: 0, mutuals: friends)
        }
        if let f = current.followers, let g = current.following {
            let m = mutuals(followers: f, following: g).count
            return Stats(followers: f.count, following: g.count, notFollowingBack: g.count - m, mutuals: m)
        }
        if let s = current.summary, current.followers == nil {
            let nfb = s.notFollowingBack ?? 0
            return Stats(followers: s.followers, following: s.following, notFollowingBack: nfb,
                         mutuals: max(0, s.following - nfb))
        }
        let followers = current.followers?.count ?? 0
        let following = current.following?.count ?? 0
        return Stats(followers: followers, following: following, notFollowingBack: 0, mutuals: 0)
    }
}
