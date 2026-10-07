// ============================================================
// LIVE ACTIVITY SETUP
// ============================================================
// 1. Add this file to both the main SocialTea target AND the
//    SocialTeaWidget target (File Inspector → Target Membership).
// 2. In Xcode's project Info tab for the SocialTea target, add:
//      NSSupportsLiveActivities   Boolean   YES
// 3. In SocialTeaWidget.swift, replace the @main placeholder
//    with SocialTeaWidgetBundle (defined at the bottom of this file).
// ============================================================

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Shared attributes (main app + widget target)

struct CleanupActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var remaining: Int
        var kept: Int
        var queued: Int
    }

    let platformName: String
}

// MARK: - Lock Screen / notification banner view

struct CleanupLiveActivityView: View {
    let context: ActivityViewContext<CleanupActivityAttributes>
    private let accent = Color(red: 0.07, green: 0.55, blue: 0.52)

    var body: some View {
        HStack(spacing: 16) {
            Label {
                Text(context.attributes.platformName)
                    .font(.footnote.weight(.semibold))
            } icon: {
                Image(systemName: "rectangle.stack.fill")
                    .foregroundStyle(accent)
            }
            Spacer()
            HStack(spacing: 14) {
                statPill(context.state.remaining, "left",   .primary)
                statPill(context.state.kept,      "kept",   accent)
                statPill(context.state.queued,    "queue",  .red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func statPill(_ value: Int, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(value)").font(.caption.weight(.bold)).foregroundStyle(tint)
            Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Dynamic Island + Widget (widget target only)

struct SocialTeaLiveActivityWidget: Widget {
    private let accent = Color(red: 0.07, green: 0.55, blue: 0.52)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CleanupActivityAttributes.self) { context in
            CleanupLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.platformName, systemImage: "rectangle.stack.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.remaining) left")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 28) {
                        expandedStat(context.state.kept,   "Kept",        accent)
                        expandedStat(context.state.queued, "To unfollow", .red)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "rectangle.stack.fill").foregroundStyle(accent)
            } compactTrailing: {
                Text("\(context.state.remaining)").font(.caption.weight(.bold))
            } minimal: {
                Text("\(context.state.remaining)").font(.caption2)
            }
        }
    }

    private func expandedStat(_ value: Int, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title3.weight(.bold)).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Control Center widget (iOS 18)

@available(iOS 18.0, *)
struct OpenCleanupControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.socialtea.control.cleanup") {
            ControlWidgetButton(action: OpenCleanupDeckIntent()) {
                Label("SocialTea Cleanup", systemImage: "rectangle.stack.fill")
            }
        }
        .displayName("SocialTea Cleanup")
        .description("Open your cleanup deck.")
    }
}

// MARK: - Widget bundle (replaces @main on SocialTeaWidget)
// When you have both the widget file and this file in the SocialTeaWidget
// target, put @main on SocialTeaWidgetBundle and remove it from SocialTeaWidget.

struct SocialTeaWidgetBundle: WidgetBundle {
    var body: some Widget {
        SocialTeaWidget()
        SocialTeaLiveActivityWidget()
        if #available(iOS 18.0, *) {
            OpenCleanupControl()
        }
    }
}
