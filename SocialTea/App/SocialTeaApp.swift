// ============================================================
// PRE-LAUNCH CHECKLIST (manual steps in Xcode)
// ============================================================
// □ Bundle ID set (com.yourdomain.socialtea)
// □ Development team + provisioning profile in Signing & Capabilities
// □ App Groups: group.com.socialtea on both main + SocialTeaWidget targets
// □ URL Types: scheme "socialtea" in main target Info tab
// □ NSSupportsLiveActivities = YES in main target Info tab
// □ BGTaskSchedulerPermittedIdentifiers: com.socialtea.refresh in main target Info tab
// □ ITSAppUsesNonExemptEncryption = NO in main target Info tab
// □ CFBundleAlternateIcons entries for dark/berry/slate icons
// □ All alternate icon PNGs added to Assets.xcassets
// □ App Store Connect: screenshots for 6.9", 6.1", iPad (12.9" Pro)
// □ Replace 0000000000 in SettingsView.swift with the real App Store ID
// □ NSUserActivityTypes array in main target Info tab:
//     com.socialtea.dashboard, com.socialtea.cleanup, com.socialtea.insights
// ============================================================

import SwiftUI
import CoreSpotlight
import TipKit

@main
struct SocialTeaApp: App {
    @State private var store          = SessionStore()
    @State private var lock           = LockManager()
    @State private var themeSettings  = ThemeSettings()
    @State private var notifications  = NotificationManager()
    @State private var subscriptions  = SubscriptionManager()
    @State private var reviewManager  = ReviewManager()
    @State private var goalManager    = GoalManager()
    @State private var historyManager = HistoryManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        try? Tips.configure()
        BGRefreshManager.registerHandler()
        SyncedPrefs.synchronize()
        ExportFile.purge()
        SocialTeaShortcuts.updateAppShortcutParameters()
    }

    private func handleIntents() {
        let defaults = UserDefaults(suiteName: WidgetDataCache.suiteName) ?? .standard
        if let raw = defaults.string(forKey: "intent.openPlatform"),
           let platform = Platform(rawValue: raw) {
            defaults.removeObject(forKey: "intent.openPlatform")
            store.selectedPlatform = platform
            store.selectedTab = .lists
        }
        if let tab = defaults.string(forKey: "intent.openTab") {
            defaults.removeObject(forKey: "intent.openTab")
            switch tab {
            case "cleanup":   store.selectedTab = .cleanup
            case "insights":  store.selectedTab = .insights
            case "dashboard": store.selectedTab = .dashboard
            default: break
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(lock)
                .environment(themeSettings)
                .environment(notifications)
                .environment(subscriptions)
                .environment(reviewManager)
                .environment(goalManager)
                .environment(historyManager)
                .tint(themeSettings.accentColor)
                .preferredColorScheme(themeSettings.colorScheme)
                .onOpenURL { url in
                    DeepLink(url: url)?.handle(store: store)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                let streak = goalManager.streakDays
                let queueCount = store.loadedPlatforms.reduce(0) { $0 + store.cleanupState($1).unfollowQueue.count }
                let totalFollowers = store.loadedPlatforms.reduce(0) { $0 + store.stats($1).followers }
                notifications.updateDigest(streak: streak, queueCount: queueCount, totalFollowers: totalFollowers)
                lock.lockIfEnabled()
                WidgetDataCache.update(from: store)
                BGRefreshManager.schedule()
                for p in store.loadedPlatforms {
                    let s = store.stats(p)
                    historyManager.record(platform: p, followers: s.followers, following: s.following)
                }
            }
            if phase == .active {
                handleIntents()
                SpotlightIndexer.reindex(using: store)
            }
        }
    }
}

// MARK: - Tab metadata (used by both TabView and NavigationSplitView)

extension SessionStore.Tab: CaseIterable {
    public static var allCases: [SessionStore.Tab] {
        [.dashboard, .lists, .cleanup, .insights, .guide]
    }
}

extension SessionStore.Tab {
    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .lists:     "Lists"
        case .cleanup:   "Cleanup"
        case .insights:  "Insights"
        case .guide:     "Guide"
        }
    }
    var symbol: String {
        switch self {
        case .dashboard: "chart.pie.fill"
        case .lists:     "person.2.fill"
        case .cleanup:   "rectangle.stack.fill"
        case .insights:  "chart.bar.xaxis"
        case .guide:     "questionmark.circle.fill"
        }
    }
}

// MARK: - Root view

struct RootView: View {
    @Environment(SessionStore.self) private var store
    @Environment(LockManager.self) private var lock
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false
    @State private var sidebarSelection: SessionStore.Tab? = .dashboard

    private var cleanupBadge: Int {
        guard !UserDefaults.standard.bool(forKey: "focus.suppressBadge") else { return 0 }
        return store.loadedPlatforms
            .filter { !$0.friendsAreMutual }
            .reduce(0) { $0 + store.cleanupDeck($1).count }
    }

    var body: some View {
        @Bindable var store = store
        @Bindable var subscriptions = subscriptions

        let mainContent = Group {
            if sizeClass == .regular {
                ipadLayout(store: store)
            } else {
                compactLayout(store: store, badge: cleanupBadge)
            }
        }

        ZStack {
            mainContent
                .blur(radius: lock.isLocked || (lock.isEnabled && scenePhase != .active) ? 20 : 0)

            if lock.isLocked {
                LockView().transition(.opacity)
            }

            // ⌘1–5 tab keyboard shortcuts (works on both iPhone and iPad)
            keyboardShortcuts(store: store)
        }
        .animation(.easeInOut(duration: 0.2), value: lock.isLocked)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-UITestSkipOnboarding") { return }
            #endif
            if !hasSeenOnboarding { showOnboarding = true }
        }
        .sheet(isPresented: $subscriptions.showPaywall) { PaywallView() }
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: { hasSeenOnboarding = true }) {
            OnboardingView()
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
            let parts = id.split(separator: ".").map(String.init)
            if let raw = parts.last, let platform = Platform(rawValue: raw) {
                store.selectedPlatform = platform
                store.selectedTab = .lists
            }
        }
        .onContinueUserActivity("com.socialtea.dashboard") { _ in store.selectedTab = .dashboard }
        .onContinueUserActivity("com.socialtea.cleanup")   { _ in store.selectedTab = .cleanup   }
        .onContinueUserActivity("com.socialtea.insights")  { _ in store.selectedTab = .insights  }
    }

    // MARK: - Compact layout (iPhone / compact iPad)

    private func compactLayout(store: SessionStore, badge: Int) -> some View {
        @Bindable var store = store
        return TabView(selection: $store.selectedTab) {
            DashboardView().tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }.tag(SessionStore.Tab.dashboard)
            ListsView().tabItem { Label("Lists", systemImage: "person.2.fill") }.tag(SessionStore.Tab.lists)
            CleanupView().tabItem { Label("Cleanup", systemImage: "rectangle.stack.fill") }.tag(SessionStore.Tab.cleanup).badge(badge)
            InsightsView().tabItem { Label("Insights", systemImage: "chart.bar.xaxis") }.tag(SessionStore.Tab.insights)
            GuideView().tabItem { Label("Guide", systemImage: "questionmark.circle.fill") }.tag(SessionStore.Tab.guide)
        }
    }

    // MARK: - Regular layout (iPad)

    @ViewBuilder
    private func ipadLayout(store: SessionStore) -> some View {
        @Bindable var store = store
        NavigationSplitView {
            List(SessionStore.Tab.allCases, id: \.self, selection: $sidebarSelection) { tab in
                Label(tab.title, systemImage: tab.symbol)
                    .badge(tab == .cleanup ? cleanupBadge : 0)
            }
            .navigationTitle("SocialTea")
            .navigationBarTitleDisplayMode(.large)
        } detail: {
            switch store.selectedTab {
            case .dashboard: DashboardView()
            case .lists:     ListsView()
            case .cleanup:   CleanupView()
            case .insights:  InsightsView()
            case .guide:     GuideView()
            }
        }
        .onChange(of: sidebarSelection) { _, tab in
            if let tab { store.selectedTab = tab }
        }
        .onChange(of: store.selectedTab) { _, tab in
            sidebarSelection = tab
        }
    }

    // MARK: - Keyboard shortcuts

    private func keyboardShortcuts(store: SessionStore) -> some View {
        Group {
            ForEach(Array(SessionStore.Tab.allCases.enumerated()), id: \.element.title) { index, tab in
                Button(tab.title) { store.selectedTab = tab }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

