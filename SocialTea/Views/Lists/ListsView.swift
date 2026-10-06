import SwiftUI

struct ListsView: View {
    @Environment(SessionStore.self) private var store
    @State private var query        = ""
    @State private var sort: SortOrder = .az
    @State private var shareItem: ShareItem?
    @State private var showImport   = false
    @State private var selectionMode  = false
    @State private var selectedIDs: Set<String> = []
    @State private var noteTarget: Person?

    var body: some View {
        @Bindable var store = store
        let platform = store.selectedPlatform
        let view     = store.selectedView
        let result   = store.result(view, for: platform)
        let people   = ListTools.sort(ListTools.search(result.people, query: query), by: sort)

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
                    if selectionMode {
                        Button("Done") { selectionMode = false; selectedIDs = [] }
                    } else {
                        Button { showImport = true } label: { Image(systemName: "square.and.arrow.down") }
                            .accessibilityLabel("Import lists")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if selectionMode {
                        Button {
                            selectedIDs = selectedIDs.count == people.count ? [] : Set(people.map(\.id))
                        } label: {
                            Text(selectedIDs.count == people.count ? "Deselect All" : "Select All")
                                .font(.subheadline)
                        }
                    } else {
                        Menu {
                            Picker("Sort", selection: $sort) {
                                ForEach(SortOrder.allCases) { s in Text(s.title).tag(s) }
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

                        Button { selectionMode = true } label: { Image(systemName: "checkmark.circle") }
                            .disabled(people.isEmpty)
                            .accessibilityLabel("Select multiple")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                selectionBar(people: people, platform: platform, view: view)
            }
            .sheet(item: $shareItem) { item in
                ActivityView(item: item).presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showImport) { ImportView(platform: platform) }
            .sheet(item: $noteTarget) { person in NoteEditorSheet(person: person) }
            .onChange(of: store.selectedPlatform) { _, _ in
                query = ""
                selectionMode = false
                selectedIDs   = []
            }
        }
    }

    // MARK: - Selection bar

    @ViewBuilder
    private func selectionBar(people: [Person], platform: Platform, view: RelationshipView) -> some View {
        if selectionMode && !selectedIDs.isEmpty {
            HStack(spacing: 12) {
                Text("\(selectedIDs.count) selected")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    let chosen = people.filter { selectedIDs.contains($0.id) }
                    UIPasteboard.general.string = chosen.map(\.username).joined(separator: "\n")
                    Haptics.success()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Menu {
                    ForEach(ExportBuilder.Format.allCases) { format in
                        Button("Export as \(format.title)") {
                            let chosen = people.filter { selectedIDs.contains($0.id) }
                            share(chosen, platform: platform, view: view, format: format)
                        }
                    }
                } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }

    private func toggleSelect(_ person: Person) {
        Haptics.selection()
        if selectedIDs.contains(person.id) { selectedIDs.remove(person.id) }
        else { selectedIDs.insert(person.id) }
    }

    // MARK: - Row wrapper (selection + note)

    private func personRow(_ person: Person, platform: Platform, view: RelationshipView) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if selectionMode {
                    Image(systemName: selectedIDs.contains(person.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selectedIDs.contains(person.id) ? Color.accentColor : Color.secondary)
                        .animation(.spring(duration: 0.2), value: selectionMode)
                }
                PersonRow(person: person, platform: platform, view: view)
                    .allowsHitTesting(!selectionMode)
            }
            .contentShape(Rectangle())
            .onTapGesture { if selectionMode { toggleSelect(person) } }

            if let note = store.note(for: person), !note.isEmpty {
                Label(note, systemImage: "note.text")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .padding(.leading, 52)
                    .padding(.bottom, 6)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { noteTarget = person } label: {
                Label(store.note(for: person) == nil ? "Add Note" : "Edit Note",
                      systemImage: "note.text")
            }
            .tint(.orange)
        }
    }

    // MARK: - Existing pieces (unchanged)

    private func viewChips(platform: Platform) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RelationshipView.allCases) { v in
                    let selected = v == store.selectedView
                    let count    = store.result(v, for: platform)
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
                           message: "This snapshot holds totals but no usernames. Import your export to see the names behind the numbers.",
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
                        personRow(person, platform: platform, view: view)
                    }
                } footer: {
                    Text("Swipe right on any row to add a private note. Tap to open their profile in \(platform.name).")
                }
            }
        }
    }

    private func secondSnapshotMessage(_ platform: Platform) -> String {
        let d = store.platformData(platform)
        if let base = d.baseline, base.followers == nil, base.summary != nil {
            return "Your current snapshot (\(base.label)) holds counts only. Import an export with names as your baseline, then a newer one later to compare."
        }
        return "You have one snapshot marked as your baseline. Download a fresh export later and import it as the newer snapshot — then this view fills in."
    }

    private func emptyMessage(_ view: RelationshipView, _ platform: Platform) -> String {
        switch view {
        case .notFollowingBack: return platform.friendsAreMutual ? view.explanation(for: platform) : "Everyone you follow follows you back."
        case .fans:             return platform.friendsAreMutual ? view.explanation(for: platform) : "You follow back everyone who follows you."
        case .mutuals:          return "No mutual follows found."
        case .unfollowed:       return "Nobody disappeared between your snapshots."
        case .newFollowers:     return "No new names between your snapshots."
        case .goneQuiet:        return "No mutuals vanished from both of your lists."
        }
    }

    private func share(_ people: [Person], platform: Platform, view: RelationshipView, format: ExportBuilder.Format) {
        let text = ExportBuilder.text(for: people, platform: platform, format: format)
        let name = ExportBuilder.fileName(platform: platform, view: view.title(for: platform), format: format)
        shareItem = ExportFile.make(text: text, fileName: name)
    }
}

// MARK: - Note editor

private struct NoteEditorSheet: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let person: Person
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Type a note…", text: $text, axis: .vertical)
                        .lineLimit(3...10)
                } header: {
                    Text(person.title)
                } footer: {
                    Text("Notes are private and session-only — they disappear when the app closes.")
                }

                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        Button(role: .destructive) { text = "" } label: {
                            Label("Clear note", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setNote(text, for: person)
                        dismiss()
                    }
                }
            }
            .onAppear { text = store.note(for: person) ?? "" }
        }
    }
}
