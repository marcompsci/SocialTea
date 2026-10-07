import SwiftUI
import Charts
import TipKit

struct InsightsView: View {
    @Environment(SessionStore.self) private var store
    @Environment(ThemeSettings.self) private var themeSettings
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(GoalManager.self) private var goalManager
    @Environment(HistoryManager.self) private var historyManager
    @State private var shareCard: ShareItem?

    private let trendChartTip = TrendChartTip()
    private let shareCardTip  = ShareCardTip()

    private struct TrendPoint: Identifiable {
        let id: UUID
        let platform: Platform
        let date: Date
        let followers: Int
    }

    private var trendPoints: [TrendPoint] {
        store.loadedPlatforms.flatMap { platform in
            historyManager.history(for: platform).map { record in
                TrendPoint(id: record.id, platform: platform, date: record.date, followers: record.followers)
            }
        }
    }

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
                            trendSection
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
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu {
                            Button { exportPDF() } label: {
                                Label("Export PDF report", systemImage: "doc.richtext")
                            }
                            if !trendPoints.isEmpty {
                                Button { exportHistory() } label: {
                                    Label("Export history as CSV", systemImage: "tablecells")
                                }
                            }
                        } label: {
                            Image(systemName: "doc.richtext")
                        }
                        .accessibilityLabel("Export options")

                        Button { shareStats() } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share stats card")
                        .popoverTip(shareCardTip)
                    }
                }
            }
            .sheet(item: $shareCard) { ActivityView(item: $0) }
            .onAppear { Task { await ShareCardTip.insightsOpened.donate() } }
            .userActivity("com.socialtea.insights", isActive: store.selectedTab == .insights) { activity in
                activity.title = "View your insights in SocialTea"
                activity.isEligibleForSearch = true
                activity.isEligibleForPrediction = true
                activity.suggestedInvocationPhrase = "Show my SocialTea insights"
            }
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
            .accessibilityLabel(store.loadedPlatforms
                .map { "\($0.name): \(store.stats($0).followers.formatted()) followers" }
                .joined(separator: ", "))
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
            .accessibilityLabel({
                let summaries = platforms.map { p -> String in
                    let pd = store.platformData(p)
                    let base = pd.baseline?.followers?.count ?? pd.baseline?.summary?.followers ?? 0
                    let newer = pd.newer?.followers?.count ?? pd.newer?.summary?.followers ?? 0
                    let delta = newer - base
                    return "\(p.name): \(delta >= 0 ? "+" : "")\(delta)"
                }
                return "Follower change chart. " + summaries.joined(separator: ", ")
            }())
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

    // MARK: - Follower trend chart

    @ViewBuilder
    private var trendSection: some View {
        let points = trendPoints
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Follower Trend").font(.headline)
                    Text("One point per import session").font(.caption).foregroundStyle(.secondary)
                }
                Chart {
                    ForEach(points) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Followers", point.followers),
                            series: .value("Platform", point.platform.name)
                        )
                        .foregroundStyle(Theme.color(for: point.platform).opacity(0.12))
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Followers", point.followers),
                            series: .value("Platform", point.platform.name)
                        )
                        .foregroundStyle(Theme.color(for: point.platform))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("Follower trend chart")
                TipView(trendChartTip, arrowEdge: .none)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
            .onAppear { TrendChartTip.isVisible = true }
        }
    }

    // MARK: - Share

    @MainActor
    private func exportPDF() {
        let platforms = store.loadedPlatforms.map { platform -> PDFReport.PlatformStats in
            let stats = store.stats(platform)
            let nfb = store.result(.notFollowingBack, for: platform)
            return PDFReport.PlatformStats(
                name: platform.name,
                followers: stats.followers,
                following: stats.following,
                followBackRatio: stats.followBackRatio,
                notFollowingBack: nfb.availability == .ready ? nfb.count : nil,
                isMutual: platform.friendsAreMutual
            )
        }
        let data = PDFReport.make(platforms: platforms)
        let name = "SocialTea-Report-\(Date().formatted(.iso8601.year().month().day())).pdf"
        shareCard = ExportFile.makeData(data, fileName: name)
    }

    @MainActor
    private func exportHistory() {
        let records = store.loadedPlatforms.flatMap { p in
            historyManager.history(for: p).map { r in
                (date: r.date, platform: r.platform, followers: r.followers, following: r.following)
            }
        }
        let csv = ExportBuilder.historyCSV(records: records)
        let name = "SocialTea-History-\(Date().formatted(.iso8601.year().month().day())).csv"
        shareCard = ExportFile.make(text: csv, fileName: name)
    }

    @MainActor
    private func shareStats() {
        let card = StatsShareCard(
            platforms: store.loadedPlatforms,
            store: store,
            accent: themeSettings.accentColor,
            streak: goalManager.streakDays
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
    var streak: Int = 0

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
                if streak > 1 {
                    Label("\(streak)-day streak", systemImage: "flame.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("·").font(.caption2).foregroundStyle(.tertiary)
                }
                Image(systemName: "lock.shield.fill").font(.caption).foregroundStyle(accent)
                Text("On-device only · SocialTea")
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
