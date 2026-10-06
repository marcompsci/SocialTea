import SwiftUI

struct DashboardView: View {
    @Environment(SessionStore.self) private var store
    @Environment(ThemeSettings.self) private var themeSettings
    @Environment(GoalManager.self) private var goalManager
    @State private var importPlatform: Platform?
    @State private var showSettings = false
    @State private var showThemePicker = false
    @State private var showGoalSheet = false
    @State private var showGlobalSearch = false

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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showGlobalSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search all platforms")

                    Button {
                        showThemePicker = true
                    } label: {
                        Image(systemName: "paintpalette")
                    }
                    .accessibilityLabel("Customize theme")

                    Button {
                        themeSettings.toggleNightMode()
                        Haptics.light()
                    } label: {
                        Image(systemName: themeSettings.nightMode ? "sun.max.fill" : "moon.fill")
                    }
                    .accessibilityLabel(themeSettings.nightMode ? "Night mode on, tap to turn off" : "Night mode off, tap to turn on")

                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(item: $importPlatform) { platform in ImportView(platform: platform) }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showThemePicker) { ThemeCustomizerSheet() }
            .sheet(isPresented: $showGlobalSearch) { GlobalSearchView() }
            .sheet(isPresented: $showGoalSheet) {
                GoalSetSheet(platform: focus, currentFollowers: store.stats(focus).followers)
            }
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
                .fill(store.loadedPlatforms.isEmpty ? Color.secondary : themeSettings.accentColor)
                .frame(width: 8, height: 8)
            Text(store.statusLabel)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            if goalManager.streakDays > 1 {
                Label("\(goalManager.streakDays)-day streak", systemImage: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
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
                    counter(stats.followers, platform.followersNoun, themeSettings.accentColor)
                    if !platform.friendsAreMutual {
                        counter(stats.following, "Following", Theme.honey)
                        counter(stats.notFollowingBack, "Not following back", Theme.berry)
                    }
                }
                Spacer(minLength: 0)
                RatioRing(ratio: platform.friendsAreMutual ? (stats.followers > 0 ? 1 : 0) : stats.followBackRatio,
                          tint: themeSettings.accentColor)
                    .frame(width: 120, height: 120)
                    .id(platform)
            }
            if let progress = goalManager.progress(followers: stats.followers, for: platform) {
                goalProgressRow(platform: platform, followers: stats.followers, progress: progress)
            } else {
                Button {
                    showGoalSheet = true
                } label: {
                    Label("Set a follower goal", systemImage: "target")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text(store.sourceLabel(platform))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
        .onTapGesture { open(platform) }
    }

    private func goalProgressRow(platform: Platform, followers: Int, progress: Double) -> some View {
        let target = goalManager.goal(for: platform) ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Goal: \(target.formatted()) \(platform.followersNoun.lowercased())",
                      systemImage: "target")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(progress >= 1 ? .green : themeSettings.accentColor)
                Button {
                    showGoalSheet = true
                } label: {
                    Image(systemName: "pencil.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            ProgressView(value: progress)
                .tint(progress >= 1 ? .green : themeSettings.accentColor)
        }
        .allowsHitTesting(true)
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

// MARK: - Goal sheet

private struct GoalSetSheet: View {
    @Environment(GoalManager.self) private var goalManager
    @Environment(\.dismiss) private var dismiss
    let platform: Platform
    let currentFollowers: Int
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Target \(platform.followersNoun.lowercased())", text: $text)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Goal for \(platform.name)")
                } footer: {
                    Text("You currently have \(currentFollowers.formatted()) \(platform.followersNoun.lowercased()). Set a number higher than that to track progress.")
                }
                if goalManager.goal(for: platform) != nil {
                    Section {
                        Button(role: .destructive) {
                            goalManager.setGoal(0, for: platform)
                            dismiss()
                        } label: {
                            Label("Remove goal", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Follower Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let n = Int(text), n > 0 { goalManager.setGoal(n, for: platform) }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let existing = goalManager.goal(for: platform) { text = "\(existing)" }
            }
        }
    }
}

// MARK: - Theme customizer sheet

private struct ThemeCustomizerSheet: View {
    @Environment(ThemeSettings.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var pickedColor: Color = Theme.tea

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ColorPicker("Accent color", selection: $pickedColor, supportsOpacity: false)
                } header: {
                    Text("Theme Color")
                } footer: {
                    Text("Changes the accent color throughout your dashboard — counters, the follow-back ring, and status indicator.")
                }

                Section("Preview") {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(pickedColor.opacity(0.15))
                                .frame(width: 52, height: 52)
                            Circle()
                                .fill(pickedColor)
                                .frame(width: 34, height: 34)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("1,234")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(pickedColor)
                            Text("Followers")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        RatioRing(ratio: 0.72, tint: pickedColor)
                            .frame(width: 72, height: 72)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button("Reset to default") {
                        pickedColor = Color(red: 0.07, green: 0.55, blue: 0.52)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Customize Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: pickedColor) { _, new in
                theme.setAccentColor(new)
            }
            .onAppear { pickedColor = theme.accentColor }
        }
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
