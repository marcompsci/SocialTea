import Foundation
import Observation

/// All imported data for this session. Held in memory only — there is deliberately no
/// persistence layer. Force-quitting the app wipes everything.
@MainActor
@Observable
final class SessionStore {

    enum Tab: Hashable { case dashboard, lists, cleanup, insights, guide }
    enum Slot: String, Hashable, Identifiable {
        case baseline, newer
        var id: String { rawValue }
        var title: String { self == .baseline ? "Older snapshot (baseline)" : "Newer snapshot" }
    }

    // MARK: Navigation

    var selectedTab: Tab = .dashboard
    var selectedPlatform: Platform = .instagram
    var selectedView: RelationshipView = .notFollowingBack

    // MARK: Data (memory only)

    private(set) var data: [Platform: PlatformData] = [:]
    private let bundledBaseline: [Platform: Snapshot]

    // MARK: Person notes (session-only)

    private(set) var notes: [String: String] = [:]

    func setNote(_ text: String, for person: Person) {
        notes[person.id] = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    func note(for person: Person) -> String? { notes[person.id] }

    // MARK: Cleanup deck state (memory only)

    struct CleanupState {
        enum Decision { case keep, unfollow }
        var keep: [Person] = []
        var unfollowQueue: [Person] = []
        var history: [(person: Person, decision: Decision)] = []
        var reviewedIDs: Set<String> = []
    }
    var cleanup: [Platform: CleanupState] = [:]

    // MARK: Init

    init(bundledBaseline: [Platform: Snapshot]? = nil) {
        self.bundledBaseline = bundledBaseline ?? SessionStore.loadBundledBaseline()
        restoreBaseline()
        #if DEBUG
        // UI tests: start with demo data on every platform.
        if ProcessInfo.processInfo.arguments.contains("-UITestDemo") {
            for p in Platform.allCases { loadDemo(p) }
        }
        // UI tests: demo names treated as real imports, to show the free-tier limits.
        if ProcessInfo.processInfo.arguments.contains("-UITestLockedSample") {
            for p in Platform.allCases {
                var pd = DemoData.data(for: p)
                pd.baseline?.isDemo = false
                pd.newer?.isDemo = false
                data[p] = pd
            }
        }
        #endif
    }

    static func loadBundledBaseline() -> [Platform: Snapshot] {
        guard let url = Bundle.main.url(forResource: "BaselineSnapshot", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return BaselineFile.load(from: data)
    }

    var hasBundledBaseline: Bool { !bundledBaseline.isEmpty }

    // MARK: Derived state

    func platformData(_ p: Platform) -> PlatformData { data[p] ?? PlatformData() }

    var loadedPlatforms: [Platform] { Platform.allCases.filter { platformData($0).isLoaded } }

    /// ONE status label, derived only from what is loaded.
    var statusLabel: String {
        let loaded = loadedPlatforms
        switch loaded.count {
        case 0: return "No lists loaded yet"
        case 1: return "1 loaded platform: \(loaded[0].name)"
        default: return "\(loaded.count) loaded platforms: \(loaded.map(\.name).joined(separator: ", "))"
        }
    }

    func stats(_ p: Platform) -> RelationshipEngine.Stats {
        RelationshipEngine.stats(platform: p, data: platformData(p))
    }

    func result(_ view: RelationshipView, for p: Platform) -> ViewResult {
        RelationshipEngine.result(view, platform: p, data: platformData(p))
    }

    /// Short description of where a platform's current numbers come from.
    func sourceLabel(_ p: Platform) -> String {
        let d = platformData(p)
        guard let current = d.current, !current.isEmpty else { return "Nothing loaded" }
        var text = current.label
        if d.canCompare, let older = d.baseline { text = "\(older.label) → \(current.label)" }
        if current.isBundledBaseline && !current.hasNames { text += " · counts only" }
        return text
    }

    // MARK: Import

    func importLists(_ files: [(name: String, data: Data)], platform: Platform, role: ListRole, slot: Slot) throws -> Int {
        var lists: [[Person]] = []
        var firstError: Error?
        for file in files {
            do {
                lists.append(try ImportParser.parse(data: file.data, fileName: file.name, role: role))
            } catch {
                firstError = firstError ?? error
            }
        }
        let merged = ImportParser.merge(lists)
        guard !merged.isEmpty else { throw firstError ?? ImportError.empty }

        var pd = platformData(platform)
        var snapshot = (slot == .baseline ? pd.baseline : pd.newer) ?? Snapshot(label: "", date: nil)
        if snapshot.isBundledBaseline || snapshot.isDemo || snapshot.isEmpty {
            snapshot = Snapshot(label: slot == .baseline ? "Imported · older" : "Imported · newer", date: Date())
        }
        if platform.friendsAreMutual {
            snapshot.followers = merged
            snapshot.following = merged
        } else if role == .followers {
            snapshot.followers = merged
        } else {
            snapshot.following = merged
        }
        snapshot.summary = nil
        snapshot.label = (slot == .baseline ? "Imported · " : "Newer · ")
            + Date().formatted(date: .abbreviated, time: .shortened)

        // A demo "newer" snapshot shouldn't linger next to real data, and vice versa.
        if slot == .baseline {
            pd.baseline = snapshot
            if pd.newer?.isDemo == true { pd.newer = nil }
        } else {
            pd.newer = snapshot
            if pd.baseline?.isDemo == true { pd.baseline = nil }
        }
        data[platform] = pd
        cleanup[platform] = nil
        return merged.count
    }

    /// Promotes the newer snapshot to be the baseline so a fresh newer import can be compared.
    func promoteNewerToBaseline(_ p: Platform) {
        var pd = platformData(p)
        guard let newer = pd.newer else { return }
        pd.baseline = newer
        pd.newer = nil
        data[p] = pd
        cleanup[p] = nil
    }

    func loadDemo(_ p: Platform) {
        data[p] = DemoData.data(for: p)
        cleanup[p] = nil
    }

    func clearNewer(_ p: Platform) {
        var pd = platformData(p)
        pd.newer = nil
        data[p] = pd
        cleanup[p] = nil
    }

    func clear(_ p: Platform) {
        data[p] = PlatformData()
        cleanup[p] = nil
    }

    /// Wipes every import and restores the labeled baseline snapshot.
    func startOver() {
        data = [:]
        cleanup = [:]
        restoreBaseline()
    }

    /// Wipes everything, including the baseline, for this session.
    func clearAll() {
        data = [:]
        cleanup = [:]
    }

    private func restoreBaseline() {
        for (platform, snapshot) in bundledBaseline {
            data[platform] = PlatformData(baseline: snapshot, newer: nil)
        }
    }

    // MARK: Cleanup deck

    func cleanupState(_ p: Platform) -> CleanupState { cleanup[p] ?? CleanupState() }

    /// Not-following-back accounts not yet reviewed, in list order.
    func cleanupDeck(_ p: Platform) -> [Person] {
        let reviewed = cleanupState(p).reviewedIDs
        return result(.notFollowingBack, for: p).people.filter { !reviewed.contains($0.id) }
    }

    func decide(_ person: Person, _ decision: CleanupState.Decision, platform p: Platform) {
        var s = cleanupState(p)
        guard !s.reviewedIDs.contains(person.id) else { return }
        s.reviewedIDs.insert(person.id)
        s.history.append((person, decision))
        switch decision {
        case .keep: s.keep.append(person)
        case .unfollow: s.unfollowQueue.append(person)
        }
        cleanup[p] = s
    }

    @discardableResult
    func undo(platform p: Platform) -> Person? {
        var s = cleanupState(p)
        guard let last = s.history.popLast() else { return nil }
        s.reviewedIDs.remove(last.person.id)
        switch last.decision {
        case .keep: s.keep.removeAll { $0.id == last.person.id }
        case .unfollow: s.unfollowQueue.removeAll { $0.id == last.person.id }
        }
        cleanup[p] = s
        return last.person
    }

    func resetCleanup(_ p: Platform) { cleanup[p] = nil }
}
