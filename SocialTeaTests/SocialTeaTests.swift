import XCTest
@testable import SocialTea

/// Hand-verified sample:
///   followers = alice, bob, carol, dave
///   following = bob, carol, erin, frank
///   → Not following back = erin, frank   (2)
///   → Fans               = alice, dave   (2)
///   → Mutuals            = bob, carol    (2)
final class RelationshipTests: XCTestCase {

    // Instagram official export, older layout (followers_1.json): array of entries with "value".
    let instagramFollowers = """
    [
      {"title": "", "media_list_data": [], "string_list_data": [{"href": "https://www.instagram.com/alice", "value": "alice", "timestamp": 1727000000}]},
      {"title": "", "media_list_data": [], "string_list_data": [{"href": "https://www.instagram.com/Bob", "value": "Bob", "timestamp": 1726000000}]},
      {"title": "", "media_list_data": [], "string_list_data": [{"href": "https://www.instagram.com/carol", "value": "carol", "timestamp": 1725000000}]},
      {"title": "", "media_list_data": [], "string_list_data": [{"href": "https://www.instagram.com/dave", "value": "dave", "timestamp": 1724000000}]}
    ]
    """

    // Instagram official export, newer layout (following.json): username in "title", href with /_u/.
    let instagramFollowing = """
    {"relationships_following": [
      {"title": "bob", "string_list_data": [{"href": "https://www.instagram.com/_u/bob", "timestamp": 1727000000}]},
      {"title": "carol", "string_list_data": [{"href": "https://www.instagram.com/_u/carol", "timestamp": 1726000000}]},
      {"title": "erin", "string_list_data": [{"href": "https://www.instagram.com/_u/erin", "timestamp": 1725000000}]},
      {"title": "", "string_list_data": [{"href": "https://www.instagram.com/_u/frank", "timestamp": 1724000000}]}
    ]}
    """

    private func parse(_ json: String, _ role: ListRole, name: String = "file.json") throws -> [Person] {
        try ImportParser.parse(data: Data(json.utf8), fileName: name, role: role)
    }

    private func names(_ people: [Person]) -> [String] { people.map(\.id).sorted() }

    func testInstagramOfficialExportCounts() throws {
        let followers = try parse(instagramFollowers, .followers, name: "followers_1.json")
        let following = try parse(instagramFollowing, .following, name: "following.json")
        XCTAssertEqual(followers.count, 4)
        XCTAssertEqual(following.count, 4)

        XCTAssertEqual(names(RelationshipEngine.notFollowingBack(followers: followers, following: following)), ["erin", "frank"])
        XCTAssertEqual(names(RelationshipEngine.fans(followers: followers, following: following)), ["alice", "dave"])
        XCTAssertEqual(names(RelationshipEngine.mutuals(followers: followers, following: following)), ["bob", "carol"])

        let data = PlatformData(baseline: Snapshot(label: "t", date: nil, followers: followers, following: following))
        let stats = RelationshipEngine.stats(platform: .instagram, data: data)
        XCTAssertEqual(stats, .init(followers: 4, following: 4, notFollowingBack: 2, mutuals: 2))
        XCTAssertEqual(stats.followBackRatio, 0.5, accuracy: 0.0001)
        XCTAssertNotNil(followers.first?.date)
    }

    func testTwoSnapshotsUnfollowedAndNew() throws {
        let olderF = ["alice", "bob", "carol", "dave"].map { Person(username: $0) }
        let olderG = ["bob", "carol", "erin"].map { Person(username: $0) }
        let newerF = ["bob", "dave", "gina", "hank"].map { Person(username: $0) }   // alice left, carol vanished
        let newerG = ["bob", "erin"].map { Person(username: $0) }                    // carol gone from both
        let data = PlatformData(
            baseline: Snapshot(label: "old", date: nil, followers: olderF, following: olderG),
            newer: Snapshot(label: "new", date: nil, followers: newerF, following: newerG))

        let unfollowed = RelationshipEngine.result(.unfollowed, platform: .instagram, data: data)
        XCTAssertEqual(names(unfollowed.people), ["alice", "carol"])
        let new = RelationshipEngine.result(.newFollowers, platform: .instagram, data: data)
        XCTAssertEqual(names(new.people), ["gina", "hank"])
        let quiet = RelationshipEngine.result(.goneQuiet, platform: .instagram, data: data)
        XCTAssertEqual(names(quiet.people), ["carol"])

        // Current lists = newer snapshot.
        let nfb = RelationshipEngine.result(.notFollowingBack, platform: .instagram, data: data)
        XCTAssertEqual(names(nfb.people), ["erin"])
    }

    func testSingleSnapshotNeedsSecond() {
        let data = PlatformData(baseline: Snapshot(label: "b", date: nil,
                                                   followers: [Person(username: "a")], following: [Person(username: "a")]))
        XCTAssertEqual(RelationshipEngine.result(.unfollowed, platform: .instagram, data: data).availability, .needsSecondSnapshot)
        XCTAssertEqual(RelationshipEngine.result(.goneQuiet, platform: .instagram, data: data).availability, .needsSecondSnapshot)
    }

    func testFacebookFriendsAreMutual() throws {
        let json = """
        {"friends_v2": [{"name": "Avery Stone", "timestamp": 1700000000}, {"name": "Jordan Lee", "timestamp": 1690000000}]}
        """
        let friends = try parse(json, .followers, name: "your_friends.json")
        XCTAssertEqual(friends.count, 2)
        let data = PlatformData(baseline: Snapshot(label: "fb", date: nil, followers: friends, following: friends))
        XCTAssertEqual(RelationshipEngine.result(.mutuals, platform: .facebook, data: data).count, 2)
        XCTAssertEqual(RelationshipEngine.result(.notFollowingBack, platform: .facebook, data: data).count, 0)
        XCTAssertEqual(RelationshipEngine.result(.fans, platform: .facebook, data: data).count, 0)
    }

    func testBundledBaselineCountsOnly() {
        let json = """
        {"label": "Snapshot · Sep 30, 2026", "date": "2026-09-30", "platforms": {
          "instagram": {"followers": 3977, "following": 777, "notFollowingBack": 191, "followerUsernames": [], "followingUsernames": []},
          "facebook": {"followers": 53, "following": 53, "notFollowingBack": 0}
        }}
        """
        let baseline = BaselineFile.load(from: Data(json.utf8))
        let ig = PlatformData(baseline: baseline[.instagram])
        let stats = RelationshipEngine.stats(platform: .instagram, data: ig)
        XCTAssertEqual(stats.followers, 3977)
        XCTAssertEqual(stats.following, 777)
        XCTAssertEqual(stats.notFollowingBack, 191)
        XCTAssertEqual(RelationshipEngine.result(.notFollowingBack, platform: .instagram, data: ig).availability, .countsOnly)
        XCTAssertEqual(RelationshipEngine.result(.notFollowingBack, platform: .instagram, data: ig).count, 191)

        let fb = PlatformData(baseline: baseline[.facebook])
        XCTAssertEqual(RelationshipEngine.stats(platform: .facebook, data: fb).followers, 53)
        XCTAssertEqual(baseline[.instagram]?.label, "Snapshot · Sep 30, 2026")
    }
}

final class ParserTests: XCTestCase {

    func testTXTOnePerLine() throws {
        let txt = "@Alice\nbob\n\nhttps://www.instagram.com/carol/\nbob\n"
        let people = try ImportParser.parse(data: Data(txt.utf8), fileName: "list.txt", role: .followers)
        XCTAssertEqual(people.map(\.id), ["alice", "bob", "carol"])
    }

    func testTikTokTextExport() throws {
        let txt = "Date: 2024-05-01 10:00:00\nUsername: skater_one\n\nDate: 2024-04-01 09:00:00\nUsername: skater_two\n"
        let people = try ImportParser.parse(data: Data(txt.utf8), fileName: "Follower.txt", role: .followers)
        XCTAssertEqual(people.map(\.id), ["skater_one", "skater_two"])
        XCTAssertNotNil(people[0].date)
    }

    func testTikTokUserDataJSONScopesToRole() throws {
        let json = """
        {"Activity": {
          "Follower List": {"FansList": [{"Date": "2024-01-01 00:00:00", "UserName": "fan1"}, {"Date": "2024-01-02 00:00:00", "UserName": "fan2"}]},
          "Following List": {"Following": [{"Date": "2024-01-03 00:00:00", "UserName": "idol1"}]}
        }}
        """
        let followers = try ImportParser.parse(data: Data(json.utf8), fileName: "user_data.json", role: .followers)
        let following = try ImportParser.parse(data: Data(json.utf8), fileName: "user_data.json", role: .following)
        XCTAssertEqual(followers.map(\.id), ["fan1", "fan2"])
        XCTAssertEqual(following.map(\.id), ["idol1"])
    }

    func testCSVWithHeaderAndQuotes() throws {
        let csv = "Full Name,Username,Date\n\"Doe, Jane\",@jane,2024-01-01\nJohn,john,\n"
        let people = try ImportParser.parse(data: Data(csv.utf8), fileName: "export.csv", role: .followers)
        XCTAssertEqual(people.map(\.id), ["jane", "john"])
        XCTAssertEqual(people.first?.displayName, "Doe, Jane")
    }

    func testCSVWithoutHeaderUsesFirstColumn() throws {
        let csv = "alpha,1\nbeta,2\n"
        let people = try ImportParser.parse(data: Data(csv.utf8), fileName: "x.csv", role: .followers)
        XCTAssertEqual(people.map(\.id), ["alpha", "beta"])
    }

    func testJSONArrayOfStrings() throws {
        let people = try ImportParser.parse(data: Data(#"["a","@B","a"]"#.utf8), fileName: "x.json", role: .following)
        XCTAssertEqual(people.map(\.id), ["a", "b"])
    }

    func testEmptyFileThrows() {
        XCTAssertThrowsError(try ImportParser.parse(data: Data("  \n".utf8), fileName: "x.txt", role: .followers))
    }

    func testMergeSplitFollowerFiles() {
        let a = [Person(username: "a"), Person(username: "b")]
        let b = [Person(username: "b"), Person(username: "c")]
        XCTAssertEqual(ImportParser.merge([a, b]).map(\.id), ["a", "b", "c"])
    }

    func testSortAndSearch() {
        let people = [Person(username: "zed", order: 0), Person(username: "Amy", order: 1), Person(username: "bo", order: 2)]
        XCTAssertEqual(ListTools.sort(people, by: .az).map(\.id), ["amy", "bo", "zed"])
        XCTAssertEqual(ListTools.sort(people, by: .za).map(\.id), ["zed", "bo", "amy"])
        XCTAssertEqual(ListTools.sort(people, by: .newest).map(\.id), ["zed", "amy", "bo"])
        XCTAssertEqual(ListTools.search(people, query: "@AM").map(\.id), ["amy"])
    }

    func testCSVExportEscapesFormulas() {
        XCTAssertEqual(ExportBuilder.csvEscape("=cmd"), "'=cmd")
        XCTAssertEqual(ExportBuilder.csvEscape("a,b"), "\"a,b\"")
    }

    func testDemoDataHasEveryView() {
        for platform in [Platform.instagram, .tiktok] {
            let data = DemoData.data(for: platform)
            for view in RelationshipView.allCases {
                let r = RelationshipEngine.result(view, platform: platform, data: data)
                XCTAssertEqual(r.availability, .ready, "\(platform) \(view)")
                XCTAssertGreaterThan(r.count, 0, "\(platform) \(view)")
            }
        }
    }
}
