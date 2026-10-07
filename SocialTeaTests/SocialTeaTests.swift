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

@MainActor
final class SessionStoreTests: XCTestCase {

    func testPersonNotes() {
        let store = SessionStore()
        let alice = Person(username: "alice")
        XCTAssertNil(store.note(for: alice))

        store.setNote("great content", for: alice)
        XCTAssertEqual(store.note(for: alice), "great content")

        store.setNote("  \n  ", for: alice) // whitespace-only clears the note
        XCTAssertNil(store.note(for: alice))

        store.setNote("updated", for: alice)
        XCTAssertEqual(store.note(for: alice), "updated")
        XCTAssertNil(store.note(for: Person(username: "bob"))) // different person is unaffected
    }

    func testClearAllAlsoWipesCleanup() {
        let store = SessionStore()
        store.loadDemo(.instagram)
        XCTAssertTrue(store.platformData(.instagram).isLoaded)
        store.clearAll()
        XCTAssertFalse(store.platformData(.instagram).isLoaded)
        XCTAssertTrue(store.loadedPlatforms.isEmpty)
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
        XCTAssertEqual(ListTools.sort(people, by: .oldest).map(\.id), ["bo", "amy", "zed"])
        XCTAssertEqual(ListTools.search(people, query: "@AM").map(\.id), ["amy"])
    }

    func testOldestSortWithDates() {
        let t1 = Date(timeIntervalSince1970: 100_000)
        let t2 = Date(timeIntervalSince1970: 500_000)
        let t3 = Date(timeIntervalSince1970: 900_000)
        let dated = [
            Person(username: "recent", date: t3, order: 0),
            Person(username: "oldest", date: t1, order: 1),
            Person(username: "middle", date: t2, order: 2),
        ]
        XCTAssertEqual(ListTools.sort(dated, by: .oldest).map(\.id),  ["oldest", "middle", "recent"])
        XCTAssertEqual(ListTools.sort(dated, by: .newest).map(\.id),  ["recent", "middle", "oldest"])
    }

    func testExportBuilderOutput() {
        let people = [
            Person(username: "alice"),
            Person(username: "bob", displayName: "Bob Smith"),
        ]
        let txt = ExportBuilder.text(for: people, platform: .instagram, format: .txt)
        XCTAssertEqual(txt, "alice\nbob\n")

        let csv = ExportBuilder.text(for: people, platform: .instagram, format: .csv)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 3)          // header + 2 rows
        XCTAssertTrue(lines[0].hasPrefix("username,"))
        XCTAssertTrue(lines[1].hasPrefix("alice,"))
        XCTAssertTrue(lines[2].contains("bob,Bob Smith,"))
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

// MARK: - FilterSet

final class FilterSetTests: XCTestCase {

    func testDefaultIsNotActive() {
        let f = FilterSet()
        XCTAssertFalse(f.isActive)
        XCTAssertEqual(f.activeCount, 0)
    }

    func testSingleDateFilter() {
        var f = FilterSet(); f.requireDate = true
        XCTAssertTrue(f.isActive)
        XCTAssertEqual(f.activeCount, 1)
    }

    func testBothFiltersActiveCount() {
        let f = FilterSet(requireDate: true, requireNote: true)
        XCTAssertEqual(f.activeCount, 2)
    }

    func testFilterPassthrough() {
        let people = [Person(username: "a"), Person(username: "b")]
        let out = ListTools.filter(people, by: FilterSet()) { _ in false }
        XCTAssertEqual(out.map(\.id), ["a", "b"])
    }

    func testFilterByDateKeepsOnlyDated() {
        let dated   = Person(username: "dated",   date: Date())
        let undated = Person(username: "undated")
        let out = ListTools.filter([dated, undated], by: FilterSet(requireDate: true)) { _ in false }
        XCTAssertEqual(out.map(\.id), ["dated"])
    }

    func testFilterByNoteKeepsOnlyNoted() {
        let a = Person(username: "a"); let b = Person(username: "b")
        let noted: Set<String> = ["a"]
        let out = ListTools.filter([a, b], by: FilterSet(requireNote: true)) { noted.contains($0.id) }
        XCTAssertEqual(out.map(\.id), ["a"])
    }

    func testFilterCombinedRequiresBoth() {
        let both      = Person(username: "both",      date: Date())
        let dateOnly  = Person(username: "date_only", date: Date())
        let noteOnly  = Person(username: "note_only")
        let neither   = Person(username: "neither")
        let noted: Set<String> = ["both", "note_only"]
        let out = ListTools.filter([both, dateOnly, noteOnly, neither],
                                   by: FilterSet(requireDate: true, requireNote: true)) { noted.contains($0.id) }
        XCTAssertEqual(out.map(\.id), ["both"])
    }
}

// MARK: - PDFReport

final class PDFReportTests: XCTestCase {

    private let sampleStats = [
        PDFReport.PlatformStats(name: "Instagram", followers: 500, following: 400,
                                followBackRatio: 0.80, notFollowingBack: 80, isMutual: false),
        PDFReport.PlatformStats(name: "Facebook",  followers: 120, following: 120,
                                followBackRatio: 1.0, notFollowingBack: nil, isMutual: true),
    ]

    func testOutputIsNonEmpty() {
        XCTAssertGreaterThan(PDFReport.make(platforms: sampleStats).count, 1000)
    }

    func testPDFMagicHeader() {
        let data = PDFReport.make(platforms: sampleStats)
        let header = String(bytes: data.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "%PDF")
    }

    func testEmptyPlatformListStillProducesValidPDF() {
        let data = PDFReport.make(platforms: [])
        let header = String(bytes: data.prefix(4), encoding: .ascii)
        XCTAssertEqual(header, "%PDF")
    }
}

// MARK: - GoalManager

@MainActor
final class GoalManagerTests: XCTestCase {

    private let goalsKey   = "goals.targets"
    private let checkInKey = "goals.lastCheckIn"
    private let streakKey  = "goals.streak"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: goalsKey)
        UserDefaults.standard.removeObject(forKey: checkInKey)
        UserDefaults.standard.removeObject(forKey: streakKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: goalsKey)
        UserDefaults.standard.removeObject(forKey: checkInKey)
        UserDefaults.standard.removeObject(forKey: streakKey)
        super.tearDown()
    }

    func testSetAndGetGoal() {
        let mgr = GoalManager()
        mgr.setGoal(1000, for: .instagram)
        XCTAssertEqual(mgr.goal(for: .instagram), 1000)
        XCTAssertNil(mgr.goal(for: .facebook))
    }

    func testRemoveGoalOnZero() {
        let mgr = GoalManager()
        mgr.setGoal(500, for: .instagram)
        mgr.setGoal(0, for: .instagram)
        XCTAssertNil(mgr.goal(for: .instagram))
    }

    func testProgressCalculation() throws {
        let mgr = GoalManager()
        mgr.setGoal(200, for: .instagram)
        let p = try XCTUnwrap(mgr.progress(followers: 100, for: .instagram))
        XCTAssertEqual(p, 0.5, accuracy: 0.0001)
    }

    func testProgressClampsAtOne() throws {
        let mgr = GoalManager()
        mgr.setGoal(100, for: .instagram)
        let p = try XCTUnwrap(mgr.progress(followers: 999, for: .instagram))
        XCTAssertEqual(p, 1.0, accuracy: 0.0001)
    }

    func testProgressNilWhenNoGoal() {
        let mgr = GoalManager()
        XCTAssertNil(mgr.progress(followers: 500, for: .instagram))
    }

    func testFirstCheckInSetsStreak1() {
        let mgr = GoalManager()
        XCTAssertEqual(mgr.streakDays, 0)
        mgr.recordCheckIn()
        XCTAssertEqual(mgr.streakDays, 1)
    }

    func testSameDayCheckInDoesNotChangeStreak() {
        UserDefaults.standard.set(Date(), forKey: checkInKey)
        UserDefaults.standard.set(5, forKey: streakKey)
        let mgr = GoalManager()
        mgr.recordCheckIn()
        XCTAssertEqual(mgr.streakDays, 5)
    }

    func testConsecutiveDayIncrementsStreak() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        UserDefaults.standard.set(yesterday, forKey: checkInKey)
        UserDefaults.standard.set(4, forKey: streakKey)
        let mgr = GoalManager()
        mgr.recordCheckIn()
        XCTAssertEqual(mgr.streakDays, 5)
    }

    func testGapResetsStreakToOne() {
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        UserDefaults.standard.set(twoDaysAgo, forKey: checkInKey)
        UserDefaults.standard.set(10, forKey: streakKey)
        let mgr = GoalManager()
        mgr.recordCheckIn()
        XCTAssertEqual(mgr.streakDays, 1)
    }
}

// MARK: - ReviewManager

@MainActor
final class ReviewManagerTests: XCTestCase {

    private let countKey   = "review.actionCount"
    private let versionKey = "review.lastPromptVersion"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: countKey)
        UserDefaults.standard.removeObject(forKey: versionKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: countKey)
        UserDefaults.standard.removeObject(forKey: versionKey)
        super.tearDown()
    }

    func testActionCountPersists() {
        let mgr = ReviewManager()
        mgr.recordAction()
        mgr.recordAction()
        XCTAssertEqual(UserDefaults.standard.integer(forKey: countKey), 2)
    }

    func testBelowThresholdNoVersionStored() {
        let mgr = ReviewManager()
        mgr.recordAction()
        mgr.recordAction()
        // Threshold is 3; 2 actions should not store a version.
        let stored = UserDefaults.standard.string(forKey: versionKey) ?? ""
        XCTAssertTrue(stored.isEmpty)
    }

    func testExistingCountRestoredOnInit() {
        UserDefaults.standard.set(2, forKey: countKey)
        let mgr = ReviewManager()
        mgr.recordAction() // now at 3 — threshold reached but no scene in tests
        XCTAssertEqual(UserDefaults.standard.integer(forKey: countKey), 3)
    }
}

// MARK: - SessionStore cleanup deck

@MainActor
final class CleanupDeckTests: XCTestCase {

    func testDecideAllKeep() {
        let store = SessionStore(bundledBaseline: [:])
        store.loadDemo(.instagram)
        let deckCount = store.cleanupDeck(.instagram).count
        XCTAssertGreaterThan(deckCount, 0)
        store.decideAll(.keep, platform: .instagram)
        XCTAssertTrue(store.cleanupDeck(.instagram).isEmpty)
        XCTAssertEqual(store.cleanupState(.instagram).keep.count, deckCount)
        XCTAssertTrue(store.cleanupState(.instagram).unfollowQueue.isEmpty)
    }

    func testDecideAllUnfollow() {
        let store = SessionStore(bundledBaseline: [:])
        store.loadDemo(.instagram)
        let deckCount = store.cleanupDeck(.instagram).count
        store.decideAll(.unfollow, platform: .instagram)
        XCTAssertEqual(store.cleanupState(.instagram).unfollowQueue.count, deckCount)
        XCTAssertTrue(store.cleanupState(.instagram).keep.isEmpty)
    }

    func testDecideAllEmptyDeckIsNoop() {
        let store = SessionStore(bundledBaseline: [:])
        store.decideAll(.keep, platform: .instagram)
        XCTAssertTrue(store.cleanupState(.instagram).keep.isEmpty)
    }
}

// MARK: - DeepLink

final class DeepLinkTests: XCTestCase {

    func testPlatformRoute() {
        let url = URL(string: "socialtea://platform/instagram")!
        if case .openPlatform(let p) = DeepLink(url: url) {
            XCTAssertEqual(p, .instagram)
        } else {
            XCTFail("Expected .openPlatform(.instagram)")
        }
    }

    func testCleanupRoute() {
        let url = URL(string: "socialtea://platform/tiktok/cleanup")!
        if case .openCleanup(let p) = DeepLink(url: url) {
            XCTAssertEqual(p, .tiktok)
        } else {
            XCTFail("Expected .openCleanup(.tiktok)")
        }
    }

    func testInsightsRoute() {
        let url = URL(string: "socialtea://insights")!
        if case .insights = DeepLink(url: url) { } else { XCTFail("Expected .insights") }
    }

    func testDashboardRoute() {
        let url = URL(string: "socialtea://dashboard")!
        if case .dashboard = DeepLink(url: url) { } else { XCTFail("Expected .dashboard") }
    }

    func testUnknownHostReturnsNil() {
        XCTAssertNil(DeepLink(url: URL(string: "socialtea://unknown")!))
    }

    func testWrongSchemeReturnsNil() {
        XCTAssertNil(DeepLink(url: URL(string: "https://socialtea.app")!))
    }

    func testInvalidPlatformReturnsNil() {
        XCTAssertNil(DeepLink(url: URL(string: "socialtea://platform/myspace")!))
    }
}

// MARK: - HistoryManager

@MainActor
final class HistoryManagerTests: XCTestCase {

    private let key = "history.snapshots"

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testRecordSingleEntry() {
        let m = HistoryManager()
        m.record(platform: .instagram, followers: 100, following: 50)
        XCTAssertEqual(m.history(for: .instagram).count, 1)
        XCTAssertEqual(m.records.first?.followers, 100)
        XCTAssertEqual(m.records.first?.following, 50)
    }

    func testRecordDedupSameDay() {
        let m = HistoryManager()
        m.record(platform: .instagram, followers: 100, following: 50)
        m.record(platform: .instagram, followers: 200, following: 80) // same day — skipped
        XCTAssertEqual(m.history(for: .instagram).count, 1)
        XCTAssertEqual(m.records.first?.followers, 100) // original value kept
    }

    func testRecordSkipsZeroFollowers() {
        let m = HistoryManager()
        m.record(platform: .instagram, followers: 0, following: 0)
        XCTAssertTrue(m.history(for: .instagram).isEmpty)
    }

    func testRecordIsolatedPerPlatform() {
        let m = HistoryManager()
        m.record(platform: .instagram, followers: 100, following: 50)
        m.record(platform: .tiktok,    followers: 200, following: 80)
        XCTAssertEqual(m.history(for: .instagram).count, 1)
        XCTAssertEqual(m.history(for: .tiktok).count, 1)
        XCTAssertTrue(m.history(for: .facebook).isEmpty)
    }

    func testClear() {
        let m = HistoryManager()
        m.record(platform: .instagram, followers: 100, following: 50)
        m.clear()
        XCTAssertTrue(m.records.isEmpty)
        XCTAssertTrue(m.history(for: .instagram).isEmpty)
    }

    func testMaxCapPerPlatform() throws {
        // Inject 35 records with distinct dates to bypass the one-per-day guard in record().
        // JSONDecoder's default Date strategy reads timeIntervalSinceReferenceDate as a Double.
        let injected: [[String: Any]] = (1...35).map { i in
            let date = Date(timeIntervalSinceNow: -Double(i) * 86400)
            return [
                "id":        UUID().uuidString,
                "date":      date.timeIntervalSinceReferenceDate,
                "platform":  "instagram",
                "followers": 100 + i,
                "following": 50
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: injected)
        UserDefaults.standard.set(data, forKey: key)

        let m = HistoryManager() // loads all 35 without trimming
        XCTAssertEqual(m.records.count, 35)

        // record() for today (not in the injected set) adds one more then trims to 30
        m.record(platform: .instagram, followers: 999, following: 100)
        XCTAssertEqual(m.history(for: .instagram).count, 30)
    }
}

// MARK: - ExportBuilder extensions

final class ExportBuilderExtendedTests: XCTestCase {

    func testJSONOutputContainsExpectedKeys() throws {
        let people = [Person(username: "alice"), Person(username: "bob", displayName: "Bob Smith")]
        let json = ExportBuilder.text(for: people, platform: .instagram, format: .json)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let array = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(array.count, 2)
        let first = try XCTUnwrap(array.first)
        XCTAssertNotNil(first["username"])
        XCTAssertNotNil(first["display_name"])
        // date and profile_url are present as null when absent — key still exists
        XCTAssertTrue(first.keys.contains("date"))
        XCTAssertTrue(first.keys.contains("profile_url"))
    }

    func testJSONEmptyInputProducesEmptyArray() {
        let json = ExportBuilder.text(for: [], platform: .instagram, format: .json)
        XCTAssertEqual(json.trimmingCharacters(in: .whitespacesAndNewlines), "[]")
    }

    func testHistoryCSVHeaderOnly() {
        let csv = ExportBuilder.historyCSV(records: [])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0], "date,platform,followers,following")
    }

    func testHistoryCSVSortedByDate() {
        let t1 = Date(timeIntervalSince1970: 100_000)
        let t2 = Date(timeIntervalSince1970: 200_000)
        let t3 = Date(timeIntervalSince1970: 300_000)
        let records = [
            (date: t3, platform: "Instagram", followers: 300, following: 100),
            (date: t1, platform: "Instagram", followers: 100, following:  50),
            (date: t2, platform: "TikTok",    followers: 200, following:  80),
        ]
        let csv = ExportBuilder.historyCSV(records: records)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 4) // header + 3 data rows
        // After sorting by date: t1 (Instagram/100), t2 (TikTok/200), t3 (Instagram/300)
        XCTAssertTrue(lines[1].contains(",Instagram,100,"))
        XCTAssertTrue(lines[2].contains(",TikTok,200,"))
        XCTAssertTrue(lines[3].contains(",Instagram,300,"))
    }

    func testHistoryCSVContainsAllFields() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let records = [(date: date, platform: "Instagram", followers: 1234, following: 567)]
        let csv = ExportBuilder.historyCSV(records: records)
        XCTAssertTrue(csv.contains("Instagram"))
        XCTAssertTrue(csv.contains("1234"))
        XCTAssertTrue(csv.contains("567"))
    }
}

// MARK: - BGRefreshManager

final class BGRefreshManagerTests: XCTestCase {

    func testIdentifierMatchesPlistKey() {
        // Verifies the identifier constant matches what must be in
        // BGTaskSchedulerPermittedIdentifiers in the app's Info.plist.
        XCTAssertEqual(BGRefreshManager.identifier, "com.socialtea.refresh")
    }
}
