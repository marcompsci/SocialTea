import SwiftUI

@main
struct SocialTeaApp: App {
    @State private var store         = SessionStore()
    @State private var lock          = LockManager()
    @State private var themeSettings = ThemeSettings()
    @State private var notifications = NotificationManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Backstop: remove any leftover Share Sheet temp file from a previous run.
        ExportFile.purge()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(lock)
                .environment(themeSettings)
                .environment(notifications)
                .tint(themeSettings.accentColor)
                .preferredColorScheme(themeSettings.colorScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { lock.lockIfEnabled() }
        }
    }
}

struct RootView: View {
    @Environment(SessionStore.self) private var store
    @Environment(LockManager.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false

    var body: some View {
        @Bindable var store = store
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
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: { hasSeenOnboarding = true }) {
            OnboardingView()
        }
    }
}
