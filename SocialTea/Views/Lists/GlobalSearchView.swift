import SwiftUI

/// Searches every loaded platform's primary relationship views at once.
struct GlobalSearchView: View {
    @Environment(SessionStore.self) private var store
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private struct Match: Identifiable {
        let id = UUID()
        let person: Person
        let platform: Platform
        let view: RelationshipView
    }

    private var matches: [Match] {
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { return [] }
        let primaryViews = RelationshipView.allCases.filter { !$0.needsTwoSnapshots }
        var seen = Set<String>()
        var results: [Match] = []
        for platform in store.loadedPlatforms {
            guard subscriptions.isUnlocked(store.platformData(platform)) else { continue }
            for view in primaryViews {
                let result = store.result(view, for: platform)
                guard result.availability == .ready else { continue }
                for person in ListTools.search(result.people, query: query) {
                    let key = "\(person.id)|\(platform.rawValue)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    results.append(Match(person: person, platform: platform, view: view))
                }
            }
        }
        return results
    }

    var body: some View {
        NavigationStack {
            List {
                if store.loadedPlatforms.isEmpty {
                    ContentUnavailableView(
                        "No Data Loaded",
                        systemImage: "magnifyingglass",
                        description: Text("Import a platform on the Dashboard to search your lists.")
                    )
                } else if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    Section {
                        Label("Type at least 2 characters to search across all loaded platforms.",
                              systemImage: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                } else if matches.isEmpty {
                    Section {
                        Text("No results for \"\(query)\"")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(store.loadedPlatforms) { platform in
                        let platformMatches = matches.filter { $0.platform == platform }
                        if !platformMatches.isEmpty {
                            Section {
                                ForEach(platformMatches) { match in
                                    HStack {
                                        PersonRow(person: match.person,
                                                  platform: match.platform,
                                                  view: match.view)
                                        Spacer(minLength: 0)
                                        Text(match.view.title(for: platform))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .padding(.leading, 4)
                                    }
                                }
                            } header: {
                                Label(platform.name, systemImage: platform.symbol)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Search All")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search across all platforms")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
