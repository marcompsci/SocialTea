import SwiftUI

struct ListsView: View {
    @Environment(SessionStore.self) private var store
    @State private var query = ""
    @State private var sort: SortOrder = .az
    @State private var shareItem: ShareItem?
    @State private var showImport = false

    var body: some View {
        @Bindable var store = store
        let platform = store.selectedPlatform
        let view = store.selectedView
        let result = store.result(view, for: platform)
        let people = ListTools.sort(ListTools.search(result.people, query: query), by: sort)

        NavigationStack {
            List {
                Section {
                    Picker("Platform", selection: $store.selectedPlatform) {
                        ForEach(Platform.allCases) { p in Text(p.name).tag(p) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                    viewChips(platform: platform)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                Section {
                    header(view: view, platform: platform, result: result)
                }

                content(result: result, people: people, platform: platform, view: view)
            }
            .listStyle(.insetGrouped)
            .navigationTitle(view.title(for: platform))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search usernames")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showImport = true } label: { Image(systemName: "square.and.arrow.down") }
                        .accessibilityLabel("Import lists")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(SortOrder.allCases) { s in
                                Text(s.title).tag(s)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort")

                    Menu {
                        ForEach(ExportBuilder.Format.allCases) { format in
                            Button("Share as \(format.title)") { share(people, platform: platform, view: view, format: format) }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(people.isEmpty)
                    .accessibilityLabel("Share list")
                }
            }
            .sheet(item: $shareItem) { item in
                ActivityView(item: item)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showImport) { ImportView(platform: platform) }
            .onChange(of: store.selectedPlatform) { _, _ in query = "" }
        }
    }

    // MARK: Pieces

    private func viewChips(platform: Platform) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RelationshipView.allCases) { v in
                    let selected = v == store.selectedView
                    let count = store.result(v, for: platform)
                    Button {
                        Haptics.selection()
                        store.selectedView = v
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: v.symbol)
                            Text(v.title(for: platform))
                            if count.availability == .ready || count.availability == .countsOnly {
                                Text(count.count.formatted())
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Capsule().fill(selected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.15)))
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(Capsule().fill(selected ? Theme.color(for: v) : Color(.secondarySystemGroupedBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func header(view: RelationshipView, platform: Platform, result: ViewResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.count.formatted())
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.color(for: view))
                    .contentTransition(.numericText())
                Text(view.title(for: platform)).font(.headline)
            }
            Text(view.explanation(for: platform))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if view == .goneQuiet {
                Label("Heuristic only — never proof of a block.", systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Text(store.sourceLabel(platform))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func content(result: ViewResult, people: [Person], platform: Platform, view: RelationshipView) -> some View {
        switch result.availability {
        case .noData:
            Section {
                NoticeCard(symbol: "tray", title: "No \(platform.name) lists loaded",
                           message: "Import your official export, or load demo data to explore.")
                Button("Import \(platform.name)") { showImport = true }
                Button("Load demo data") { store.loadDemo(platform) }
            }
        case .countsOnly:
            Section {
                NoticeCard(symbol: "number.circle",
                           title: "Counts only",
                           message: "This snapshot holds totals but no usernames, so there's no list to show. Import your export to see the names behind the number.",
                           tint: Theme.honey)
                Button("Import \(platform.name) export") { showImport = true }
            }
        case .needsSecondSnapshot:
            Section {
                NoticeCard(symbol: "clock.arrow.2.circlepath",
                           title: "A second snapshot is needed",
                           message: secondSnapshotMessage(platform),
                           tint: Theme.tea)
                Button("Import a newer snapshot") { showImport = true }
            }
        case .needsFollowingList:
            Section {
                NoticeCard(symbol: "doc.badge.plus",
                           title: "Both lists needed",
                           message: "This view compares who follows you with who you follow. Import both your followers and following lists.",
                           tint: Theme.honey)
                Button("Import the missing list") { showImport = true }
            }
        case .ready:
            if result.people.isEmpty {
                Section {
                    NoticeCard(symbol: "checkmark.seal", title: "Nobody here", message: emptyMessage(view, platform))
                }
            } else if people.isEmpty {
                Section {
                    Text("No matches for \"\(query)\"").foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(people) { person in
                        PersonRow(person: person, platform: platform, view: view)
                    }
                } footer: {
                    Text("Tap anyone to open their profile in \(platform.name). Follow, unfollow and block happen in the official app — SocialTea never acts on your account.")
                }
            }
        }
    }

    private func secondSnapshotMessage(_ platform: Platform) -> String {
        let d = store.platformData(platform)
        if let base = d.baseline, base.followers == nil, base.summary != nil {
            return "Your current snapshot (\(base.label)) holds counts only. Import an export with names as your baseline, then a newer one later to compare."
        }
        return "You have one snapshot, and it's marked as your baseline. Download a fresh export later and import it as the newer snapshot — then this view fills in."
    }

    private func emptyMessage(_ view: RelationshipView, _ platform: Platform) -> String {
        switch view {
        case .notFollowingBack: return platform.friendsAreMutual ? view.explanation(for: platform) : "Everyone you follow follows you back."
        case .fans: return platform.friendsAreMutual ? view.explanation(for: platform) : "You follow back everyone who follows you."
        case .mutuals: return "No mutual follows found."
        case .unfollowed: return "Nobody disappeared between your snapshots."
        case .newFollowers: return "No new names between your snapshots."
        case .goneQuiet: return "No mutuals vanished from both of your lists."
        }
    }

    private func share(_ people: [Person], platform: Platform, view: RelationshipView, format: ExportBuilder.Format) {
        let text = ExportBuilder.text(for: people, platform: platform, format: format)
        let name = ExportBuilder.fileName(platform: platform, view: view.title(for: platform), format: format)
        shareItem = ExportFile.make(text: text, fileName: name)
    }
}
