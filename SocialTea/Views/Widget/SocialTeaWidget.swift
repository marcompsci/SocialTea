// ============================================================
// WIDGET SETUP — read before building
// ============================================================
// This file belongs in a separate Widget Extension target, NOT the main app.
//
// Steps to activate:
//   1. Xcode → File → New → Target → Widget Extension
//      Name: "SocialTeaWidget"  |  Check "Include Live Activity"
//   2. Main app target → Signing & Capabilities → + App Groups
//      Add: "group.com.socialtea"
//   3. SocialTeaWidget target → same capability, same group name
//   4. Move this file to the new SocialTeaWidget folder in Xcode
//      (drag from SocialTea/Views/Widget to SocialTeaWidget group)
//   5. Also add WidgetDataCache.swift, CleanupLiveActivity.swift, AND
//      SocialTeaIntents.swift to the SocialTeaWidget target (File Inspector → Target Membership)
//   6. Add "@main" on the line above "struct SocialTeaWidgetBundle: WidgetBundle {"
//      in CleanupLiveActivity.swift — that bundle includes both widgets.
// ============================================================

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline provider (configurable per-platform)

struct SocialTeaProvider: AppIntentTimelineProvider {
    typealias Intent = SelectPlatformIntent

    func placeholder(in context: Context) -> SocialTeaEntry { .placeholder }

    func snapshot(for configuration: SelectPlatformIntent, in context: Context) async -> SocialTeaEntry {
        let all = WidgetDataCache.load()
        return SocialTeaEntry(date: Date(), stats: filtered(all, by: configuration.platform))
    }

    func timeline(for configuration: SelectPlatformIntent, in context: Context) async -> Timeline<SocialTeaEntry> {
        let all = WidgetDataCache.load()
        let entry = SocialTeaEntry(date: Date(), stats: filtered(all, by: configuration.platform))
        let next  = Calendar.current.date(byAdding: .hour, value: 6, to: Date())!
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func filtered(_ stats: [WidgetDataCache.Entry], by platform: PlatformAppEnum?) -> [WidgetDataCache.Entry] {
        guard let p = platform else { return stats }
        return stats.filter { $0.platform.lowercased() == p.displayName.lowercased() }
    }
}

// MARK: - Entry

struct SocialTeaEntry: TimelineEntry {
    let date:  Date
    let stats: [WidgetDataCache.Entry]

    static let placeholder = SocialTeaEntry(date: Date(), stats: [
        .init(platform: "Instagram", followers: 1_234, following: 892,  followBackRatio: 0.72, lastUpdated: Date()),
        .init(platform: "TikTok",    followers:   567, following: 320,  followBackRatio: 0.88, lastUpdated: Date()),
    ])
}

// MARK: - Widget views

struct SocialTeaWidgetView: View {
    let entry: SocialTeaEntry
    @Environment(\.widgetFamily) private var family

    private let accent = Color(red: 0.07, green: 0.55, blue: 0.52)

    var body: some View {
        switch family {
        case .systemSmall:           smallView
        case .systemMedium:          mediumView
        case .accessoryCircular:     circularView
        case .accessoryRectangular:  rectangularView
        case .accessoryInline:       inlineView
        default:                     smallView
        }
    }

    // MARK: Small (2×2)

    private var smallView: some View {
        ZStack {
            accent.opacity(0.08)
            if entry.stats.isEmpty {
                emptyPrompt
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "cup.and.saucer.fill").foregroundStyle(accent).font(.caption)
                        Text("SocialTea").font(.caption2.weight(.semibold))
                        Spacer()
                    }
                    Spacer()
                    ForEach(entry.stats.prefix(2), id: \.platform) { stat in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(stat.followers.formatted())
                                .font(.title2.weight(.bold)).foregroundStyle(accent)
                            Text(stat.platform).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(12)
            }
        }
        .widgetBackground(Color(.systemBackground))
    }

    // MARK: Medium (4×2) — each platform cell is an interactive button (iOS 17+)

    private var mediumView: some View {
        ZStack {
            accent.opacity(0.06)
            if entry.stats.isEmpty {
                emptyPrompt
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "cup.and.saucer.fill").foregroundStyle(accent)
                        Text("SocialTea").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("Updated \(entry.date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Divider()
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: min(entry.stats.count, 3)),
                        spacing: 4
                    ) {
                        ForEach(entry.stats, id: \.platform) { stat in
                            platformCell(stat)
                        }
                    }
                }
                .padding(14)
            }
        }
        .widgetBackground(Color(.systemBackground))
    }

    @ViewBuilder
    private func platformCell(_ stat: WidgetDataCache.Entry) -> some View {
        if let platformEnum = PlatformAppEnum(rawValue: stat.platform.lowercased()) {
            let intent: OpenPlatformIntent = {
                var i = OpenPlatformIntent()
                i.platform = platformEnum
                return i
            }()
            Button(intent: intent) { platformStatStack(stat) }
                .buttonStyle(.plain)
        } else {
            platformStatStack(stat)
        }
    }

    private func platformStatStack(_ stat: WidgetDataCache.Entry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.followers.formatted())
                .font(.title3.weight(.bold)).foregroundStyle(accent)
            Text(stat.platform).font(.caption2).foregroundStyle(.secondary)
            if stat.followBackRatio > 0 {
                Text("\(Int(stat.followBackRatio * 100))% back")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Lock screen inline (single text row above clock)

    private var inlineView: some View {
        let total = entry.stats.reduce(0) { $0 + $1.followers }
        return Label {
            if total > 0 {
                Text("\(total.formatted(.number.notation(.compactName))) followers")
            } else {
                Text("SocialTea — open to import")
            }
        } icon: {
            Image(systemName: "cup.and.saucer.fill")
        }
    }

    // MARK: Lock screen circular

    private var circularView: some View {
        let total = entry.stats.reduce(0) { $0 + $1.followers }
        return ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(total.formatted(.number.notation(.compactName)))
                    .font(.caption.weight(.bold))
                Text("followers").font(.system(size: 7))
            }
        }
    }

    // MARK: Lock screen rectangular

    private var rectangularView: some View {
        HStack(spacing: 8) {
            Image(systemName: "cup.and.saucer.fill").foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("SocialTea").font(.caption.weight(.semibold))
                if let first = entry.stats.first {
                    Text("\(first.followers.formatted()) \(first.platform) followers")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Open to import your data")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Empty state

    private var emptyPrompt: some View {
        VStack(spacing: 6) {
            Image(systemName: "cup.and.saucer").foregroundStyle(accent).font(.title2)
            Text("Open SocialTea to import data")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Background helper

extension View {
    @ViewBuilder
    func widgetBackground(_ color: Color) -> some View {
        if #available(iOS 17, *) {
            containerBackground(color, for: .widget)
        } else {
            background(color)
        }
    }
}

// MARK: - Widget entry point

struct SocialTeaWidget: Widget {
    let kind = "SocialTeaWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectPlatformIntent.self, provider: SocialTeaProvider()) { entry in
            SocialTeaWidgetView(entry: entry)
        }
        .configurationDisplayName("SocialTea")
        .description("Quick glance at your follower stats. Long-press to choose a platform.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
