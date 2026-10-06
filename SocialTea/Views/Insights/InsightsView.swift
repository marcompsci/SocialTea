import SwiftUI
import Charts

struct InsightsView: View {
    @Environment(SessionStore.self) private var store
    @Environment(ThemeSettings.self) private var themeSettings
    @Environment(SubscriptionManager.self) private var subscriptions
    @State private var shareCard: ShareItem?

    private var unlocked: Bool {
        subscriptions.isUnlocked(platforms: store.loadedPlatforms.map { store.platformData($0) })
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.loadedPlatforms.isEmpty {
                    ContentUnavailableView(
                        "No Data Yet",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Import data on the Dashboard to see your insights here.")
                    )
                } else if !unlocked {
                    ScrollView {
                        ProLockedCard(title: "Insights is part of Pro",
                                      message: "Charts across every platform, follower changes between exports, and a shareable stats card.")
                            .padding()
                    }
                    .background(Color(.systemGroupedBackground))
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            followerBarChart
                            if hasComparisonData { growthChart }
                            followBackCard
                        }
                        .padding()
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Insights")
            .toolbar {
                if !store.loadedPlatforms.isEmpty && unlocked {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { shareStats() } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share stats")
                    }
                }
            }
            .sheet(item: $shareCard) { ActivityView(item: $0) }
        }
    }

    // MARK: - Followers bar chart

    private var followerBarChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Followers").font(.headline)
            Chart {
                ForEach(store.loadedPlatforms) { platform in
                    let count = store.stats(platform).followers
                    BarMark(
                        x: .value("Platform", platform.name),
                        y: .value("Count", count)
                    )
                    .foregroundStyle(Theme.color(for: platform).gradient)
                    .cornerRadius(8)
                    .annotation(position: .top, alignment: .center) {
                        Text(count.formatted())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 180)
            .chartYAxis(.hidden)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Growth comparison chart

    private var hasComparisonData: Bool {
        store.loadedPlatforms.contains { store.platformData($0).canCompare }
    }

    private var growthChart: some View {
        let platforms = store.loadedPlatforms.filter { store.platformData($0).canCompare }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Follower Change").font(.headline)
                Text("Newer snapshot vs. baseline").font(.caption).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(platforms) { platform in
                    let pd = store.platformData(platform)
                    let base = pd.baseline?.followers?.count ?? pd.baseline?.summary?.followers ?? 0
                    let newer = pd.newer?.followers?.count ?? pd.newer?.summary?.followers ?? 0
                    let delta = newer - base
                    BarMark(
                        x: .value("Platform", platform.name),
                        y: .value("Change", delta)
                    )
                    .foregroundStyle(delta >= 0 ? Color.green.gradient : Color.red.gradient)
                    .cornerRadius(8)
                    .annotation(position: delta >= 0 ? .top : .bottom, alignment: .center) {
                        Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(delta >= 0 ? Color.green : Color.red)
                    }
                }
            }
            .frame(height: 160)
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Follow-back ratio grid

    @ViewBuilder
    private var followBackCard: some View {
        let platforms = store.loadedPlatforms.filter { !$0.friendsAreMutual }
        if !platforms.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Follow-back Ratio").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(platforms) { platform in
                        VStack(spacing: 8) {
                            RatioRing(ratio: store.stats(platform).followBackRatio,
                                      tint: Theme.color(for: platform))
                                .frame(width: 90, height: 90)
                            Text(platform.name)
                                .font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.tertiarySystemGroupedBackground)))
                    }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    // MARK: - Share

    @MainActor
    private func shareStats() {
        let card = StatsShareCard(
            platforms: store.loadedPlatforms,
            store: store,
            accent: themeSettings.accentColor
        )
        let renderer = ImageRenderer(content: card.frame(width: 360))
        renderer.scale = 3.0
        guard let image = renderer.uiImage,
              let png = image.pngData(),
              let item = ExportFile.makeData(png, fileName: "socialtea-stats.png") else { return }
        shareCard = item
    }
}

// MARK: - Share card (rendered to image)

private struct StatsShareCard: View {
    let platforms: [Platform]
    let store: SessionStore
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(accent)
                Text("SocialTea").font(.headline.weight(.bold))
                Spacer()
                Text(Date().formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))

            Divider()

            // Platform rows
            VStack(spacing: 0) {
                ForEach(platforms) { platform in
                    let stats = store.stats(platform)
                    HStack(spacing: 12) {
                        PlatformBadge(platform: platform)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(platform.name).font(.subheadline.weight(.semibold))
                            Text("\(stats.followers) \(platform.followersNoun.lowercased())")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !platform.friendsAreMutual {
                            Text("\(Int(stats.followBackRatio * 100))% follow back")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(accent)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    if platform != platforms.last {
                        Divider().padding(.leading, 72)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))

            Divider()

            // Footer
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill").font(.caption).foregroundStyle(accent)
                Text("Analyzed privately on-device · SocialTea")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
