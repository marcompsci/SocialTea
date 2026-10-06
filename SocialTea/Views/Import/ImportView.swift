import SwiftUI
import UniformTypeIdentifiers

/// Per-platform import: older (baseline) and optional newer snapshot, each with
/// followers + following. Files are read once into memory and never copied or kept.
struct ImportView: View {
    let platform: Platform
    @Environment(SessionStore.self) private var store
    @Environment(ReviewManager.self) private var reviewManager
    @Environment(GoalManager.self) private var goalManager
    @Environment(\.dismiss) private var dismiss

    private struct Target: Equatable {
        var slot: SessionStore.Slot
        var role: ListRole
    }

    @State private var target: Target?
    @State private var showPicker = false
    @State private var message: (text: String, isError: Bool)?
    @State private var confirmClear = false

    private static let types: [UTType] = [.json, .commaSeparatedText, .plainText, .text, .utf8PlainText]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PrivacyPromise(compact: true)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if let message {
                    Section {
                        Label(message.text, systemImage: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(message.isError ? Color.orange : Theme.tea)
                            .font(.subheadline)
                    }
                }

                snapshotSection(.baseline,
                                footer: "Start here. This is the snapshot everything else is compared against.")
                snapshotSection(.newer,
                                footer: "Optional. Import a later export to see who unfollowed you and who's new.")

                Section {
                    Button {
                        store.loadDemo(platform)
                        Haptics.light()
                        message = ("Demo data loaded for \(platform.name).", false)
                    } label: {
                        Label("Load demo data", systemImage: "sparkles")
                    }
                    if store.platformData(platform).newer != nil {
                        Button {
                            store.promoteNewerToBaseline(platform)
                            message = ("Newer snapshot is now your baseline. Import a fresh newer one to compare.", false)
                        } label: {
                            Label("Make newer snapshot the baseline", systemImage: "arrow.up.circle")
                        }
                        Button(role: .destructive) {
                            store.clearNewer(platform)
                            message = ("Newer snapshot removed.", false)
                        } label: {
                            Label("Remove newer snapshot", systemImage: "minus.circle")
                        }
                    }
                    Button(role: .destructive) { confirmClear = true } label: {
                        Label("Clear \(platform.name)", systemImage: "trash")
                    }
                } footer: {
                    Text(howToText)
                }
            }
            .navigationTitle("Import \(platform.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(isPresented: $showPicker,
                          allowedContentTypes: Self.types,
                          allowsMultipleSelection: true) { result in
                handle(result)
            }
            .confirmationDialog("Clear all \(platform.name) lists for this session?",
                                isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear \(platform.name)", role: .destructive) {
                    store.clear(platform)
                    message = ("\(platform.name) cleared.", false)
                }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func snapshotSection(_ slot: SessionStore.Slot, footer: String) -> some View {
        let snapshot = slot == .baseline ? store.platformData(platform).baseline : store.platformData(platform).newer
        Section {
            if let snapshot {
                LabeledContent("Loaded", value: snapshot.label)
                    .font(.footnote)
            }
            if platform.friendsAreMutual {
                pickerRow(slot: slot, role: .followers, title: "Friends list",
                          count: snapshot?.followers?.count ?? snapshot?.summary?.followers,
                          countsOnly: snapshot?.followers == nil && snapshot?.summary != nil)
            } else {
                pickerRow(slot: slot, role: .followers, title: "Followers",
                          count: snapshot?.followers?.count ?? snapshot?.summary?.followers,
                          countsOnly: snapshot?.followers == nil && snapshot?.summary != nil)
                pickerRow(slot: slot, role: .following, title: "Following",
                          count: snapshot?.following?.count ?? snapshot?.summary?.following,
                          countsOnly: snapshot?.following == nil && snapshot?.summary != nil)
            }
        } header: {
            Text(slot.title)
        } footer: {
            Text(footer)
        }
    }

    private func pickerRow(slot: SessionStore.Slot, role: ListRole, title: String, count: Int?, countsOnly: Bool) -> some View {
        Button {
            target = Target(slot: slot, role: role)
            showPicker = true
        } label: {
            HStack {
                Label(title, systemImage: "doc.badge.plus")
                Spacer()
                if let count {
                    Text(countsOnly ? "\(count.formatted()) · counts only" : count.formatted())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Choose file").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityHint("Opens the file picker. JSON, CSV, or TXT.")
        .dropDestination(for: URL.self) { urls, _ in
            handleDropped(urls: urls, slot: slot, role: role)
        }
    }

    private func handleDropped(urls: [URL], slot: SessionStore.Slot, role: ListRole) -> Bool {
        guard !urls.isEmpty else { return false }
        target = Target(slot: slot, role: role)
        handle(.success(urls))
        return true
    }

    private var howToText: String {
        switch platform {
        case .instagram:
            return "Instagram: Settings → Accounts Centre → Your information and permissions → Download your information → choose JSON. Unzip it in Files, then pick followers_1.json (and any followers_2.json) for Followers and following.json for Following."
        case .facebook:
            return "Facebook: Settings → Accounts Centre → Your information and permissions → Download your information → Friends → JSON. Unzip it in Files, then pick your_friends.json (or friends.json)."
        case .tiktok:
            return "TikTok: Profile → ☰ → Settings and privacy → Account → Download your data → JSON. Pick user_data.json (or the Follower / Following text files) for each list."
        }
    }

    // MARK: Import handling

    private func handle(_ result: Result<[URL], Error>) {
        guard let target else { return }
        switch result {
        case .failure(let error):
            message = (error.localizedDescription, true)
        case .success(let urls):
            guard !urls.isEmpty else { return }
            var files: [(name: String, data: Data)] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    files.append((url.lastPathComponent, data))
                }
            }
            do {
                let count = try store.importLists(files, platform: platform, role: target.role, slot: target.slot)
                reviewManager.recordAction()
                goalManager.recordCheckIn()
                Haptics.success()
                let noun = platform.friendsAreMutual ? "friends" : target.role.rawValue
                message = ("Imported \(count.formatted()) \(noun) from \(files.count == 1 ? files[0].name : "\(files.count) files").", false)
            } catch {
                Haptics.warning()
                message = ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription, true)
            }
        }
    }
}
