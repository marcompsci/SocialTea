import SwiftUI

@main
struct SocialTeaApp: App {
    @State private var store         = SessionStore()
    @State private var lock          = LockManager()
    @State private var themeSettings = ThemeSettings()
    @State private var notifications = NotificationManager()
    @State private var subscriptions = SubscriptionManager()
    @State private var reviewManager  = ReviewManager()
    @State private var goalManager    = GoalManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ExportFile.purge()
        SocialTeaShortcuts.updateAppShortcutParameters()
    }

    private func handlePlatformIntent() {
        let defaults = UserDefaults(suiteName: WidgetDataCache.suiteName) ?? .standard
        guard let raw = defaults.string(forKey: "intent.openPlatform"),
              let platform = Platform(rawValue: raw) else { return }
        defaults.removeObject(forKey: "intent.openPlatform")
        store.selectedPlatform = platform
        store.selectedTab = .lists
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
            }
            if phase == .active {
                handlePlatformIntent()
            }
        }
    }
}

struct RootView: View {
    @Environment(SessionStore.self) private var store
    @Environment(LockManager.self) private var lock
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false

    private var cleanupBadge: Int {
        store.loadedPlatforms
            .filter { !$0.friendsAreMutual }
            .reduce(0) { $0 + store.cleanupDeck($1).count }
    }

    var body: some View {
        @Bindable var store = store
        @Bindable var subscriptions = subscriptions
        ZStack {
            TabView(selection: $store.selectedTab) {
                DashboardView()
                    .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }
                    .tag(SessionStore.Tab.dashboard)
                ListsView()
                    .tabItem { Label("Lists", systemImage: "person.2.fill") }
                    .tag(SessionStore.Tab.lists)
                CleanupView()
                    .tabItem { Label("Cleanup", systemImage: "rectangle.stack.fill") }
                    .tag(SessionStore.Tab.cleanup)
                    .badge(cleanupBadge)
                InsightsView()
                    .tabItem { Label("Insights", systemImage: "chart.bar.xaxis") }
                    .tag(SessionStore.Tab.insights)
                GuideView()
                    .tabItem { Label("Guide", systemImage: "questionmark.circle.fill") }
                    .tag(SessionStore.Tab.guide)
            }
            // Hide content in the app switcher when a lock is on.
            .blur(radius: lock.isLocked || (lock.isEnabled && scenePhase != .active) ? 20 : 0)

            if lock.isLocked {
                LockView()
                    .transition(.opacity)
            }
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
    }
}
