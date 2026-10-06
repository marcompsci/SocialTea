import SwiftUI

struct DashboardView: View {
    @Environment(SessionStore.self) private var store
    @State private var importPlatform: Platform?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    statusHeader
                    if store.loadedPlatforms.isEmpty {
                        emptyState
                    } else {
                        totalsCard
                    }
                    ForEach(Platform.allCases) { platform in
                        PlatformCard(platform: platform,
                                     onOpen: { open(platform) },
                                     onImport: { importPlatform = platform })
                    }
                    PrivacyPromise()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("SocialTea")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(item: $importPlatform) { platform in
                ImportView(platform: platform)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private func open(_ platform: Platform) {
        Haptics.selection()
        store.selectedPlatform = platform
        store.selectedTab = .lists
    }

    // MARK: Pieces

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.loadedPlatforms.isEmpty ? Color.secondary : Theme.tea)
                .frame(width: 8, height: 8)
            Text(store.statusLabel)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.gradient)
            Text("Spill the tea on your follows")
                .font(.title3.weight(.bold))
            Text("Import your official data export, or tap Demo on any platform to look around first.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                store.selectedTab = .guide
            } label: {
                Label("How do I get my export?", systemImage: "questionmark.circle")
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var focus: Platform {
        store.loadedPlatforms.contains(store.selectedPlatform) ? store.selectedPlatform : (store.loadedPlatforms.first ?? .instagram)
    }

    private var totalsCard: some View {
        let platform = focus
        let stats = store.stats(platform)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(platform.name).font(.headline)
                Spacer()
                if store.loadedPlatforms.count > 1 {
                    Menu {
                        ForEach(store.loadedPlatforms) { p in
                            Button(p.name) { store.selectedPlatform = p }
                        }
                    } label: {
                        Label("Switch", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                    }
                }
            }
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    counter(stats.followers, platform.followersNoun, Theme.tea)
                    if !platform.friendsAreMutual {
                        counter(stats.following, "Following", Theme.honey)
                        counter(stats.notFollowingBack, "Not following back", Theme.berry)
                    }
                }
                Spacer(minLength: 0)
                RatioRing(ratio: platform.friendsAreMutual ? (stats.followers > 0 ? 1 : 0) : stats.followBackRatio)
                    .frame(width: 120, height: 120)
                    .id(platform)
            }
            Text(store.sourceLabel(platform))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
        .onTapGesture { open(platform) }
    }

    private func counter(_ value: Int, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AnimatedCounter(value: value)
                .foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Platform card

private struct PlatformCard: View {
    @Environment(SessionStore.self) private var store
    let platform: Platform
    let onOpen: () -> Void
    let onImport: () -> Void

    var body: some View {
        let loaded = store.platformData(platform).isLoaded
        let stats = store.stats(platform)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PlatformBadge(platform: platform)
                VStack(alignment: .leading, spacing: 2) {
                    Text(platform.name).font(.headline)
                    Text(store.sourceLabel(platform))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if loaded {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            if loaded {
                HStack {
                    mini(stats.followers, platform.followersNoun)
                    if !platform.friendsAreMutual {
                        mini(stats.following, "Following")
                        mini(stats.notFollowingBack, "Not back")
                    }
                }
            }
            HStack {
                Button(action: onImport) {
                    Label(loaded ? "Import / replace" : "Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.color(for: platform))
                Button {
                    Haptics.light()
                    store.loadDemo(platform)
                } label: {
                    Label("Demo", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .font(.subheadline)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture { if loaded { onOpen() } }
        .accessibilityAction(named: "Open lists") { onOpen() }
    }

    private func mini(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AnimatedCounter(value: value, font: .system(.title3, design: .rounded).weight(.bold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
