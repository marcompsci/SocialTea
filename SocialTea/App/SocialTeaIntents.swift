import AppIntents
import WidgetKit

// MARK: - Platform enum

enum PlatformAppEnum: String, AppEnum {
    case instagram
    case facebook
    case tiktok

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Platform")
    static var caseDisplayRepresentations: [PlatformAppEnum: DisplayRepresentation] = [
        .instagram: "Instagram",
        .facebook: "Facebook",
        .tiktok: "TikTok"
    ]

    var displayName: String {
        switch self {
        case .instagram: return "Instagram"
        case .facebook: return "Facebook"
        case .tiktok: return "TikTok"
        }
    }
}

// MARK: - Check follower count intent

struct CheckFollowerCountIntent: AppIntent {
    static var title: LocalizedStringResource = "Check follower count"
    static var description = IntentDescription(
        "Shows the last-known follower count for a social platform from SocialTea.",
        categoryName: "Information"
    )
    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$platform) follower count")
    }

    @Parameter(title: "Platform", default: .instagram)
    var platform: PlatformAppEnum

    func perform() async throws -> some ReturnsValue<String> {
        let entries = WidgetDataCache.load()
        let name = platform.displayName

        if let entry = entries.first(where: { $0.platform == name }) {
            let count = entry.followers
            let noun = platform == .facebook ? "friends" : "followers"
            return .result(value: "\(name): \(count.formatted()) \(noun).")
        }

        return .result(value: "No \(name) data cached yet. Open SocialTea and import your lists first.")
    }
}

// MARK: - Open platform intent (used by interactive widget button, iOS 17+)

/// Writes the desired platform to shared UserDefaults then opens the app.
/// The app reads this on foreground and navigates to the right platform.
struct OpenPlatformIntent: AppIntent {
    static var title: LocalizedStringResource = "Open platform in SocialTea"
    static var openAppWhenRun = true

    @Parameter(title: "Platform", default: .instagram)
    var platform: PlatformAppEnum

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: WidgetDataCache.suiteName) ?? .standard
        defaults.set(platform.rawValue, forKey: "intent.openPlatform")
        return .result()
    }
}

// MARK: - Widget configuration intent

struct SelectPlatformIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Platform"
    static var description = IntentDescription("Choose which platform to display.")

    @Parameter(title: "Platform")
    var platform: PlatformAppEnum?
}

// MARK: - Open cleanup deck intent (Control Center widget, iOS 18+)

struct OpenCleanupDeckIntent: AppIntent {
    static var title: LocalizedStringResource = "Open SocialTea Cleanup"
    static var description = IntentDescription("Opens the cleanup deck in SocialTea.", categoryName: "Navigation")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: WidgetDataCache.suiteName) ?? .standard
        defaults.set("cleanup", forKey: "intent.openTab")
        return .result()
    }
}

// MARK: - Platform entity + query (Shortcuts / Spotlight typed lookup)

struct PlatformEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Social Platform")
    static var defaultQuery = PlatformEntityQuery()

    var id: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(platform.displayName)") }

    let platform: PlatformAppEnum

    init(_ platform: PlatformAppEnum) {
        self.id = platform.rawValue
        self.platform = platform
    }
}

struct PlatformEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PlatformEntity] {
        identifiers.compactMap { PlatformAppEnum(rawValue: $0).map { PlatformEntity($0) } }
    }

    func suggestedEntities() async throws -> [PlatformEntity] {
        [.instagram, .facebook, .tiktok].map { PlatformEntity($0) }
    }
}

// MARK: - Get platform stats via entity

struct GetPlatformStatsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get platform stats"
    static var description = IntentDescription("Fetches follower stats for a social platform.", categoryName: "Information")
    static var parameterSummary: some ParameterSummary {
        Summary("Get stats for \(\.$platform)")
    }

    @Parameter(title: "Social Platform")
    var platform: PlatformEntity

    func perform() async throws -> some ReturnsValue<String> {
        let entries = WidgetDataCache.load()
        let name = platform.platform.displayName
        if let entry = entries.first(where: { $0.platform == name }) {
            let noun = platform.platform == .facebook ? "friends" : "followers"
            return .result(value: "\(name): \(entry.followers.formatted()) \(noun), \(entry.following.formatted()) following.")
        }
        return .result(value: "No \(name) data yet. Open SocialTea and import first.")
    }
}

// MARK: - App Shortcuts (Siri phrases + Spotlight)

struct SocialTeaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckFollowerCountIntent(),
            phrases: [
                "Check my \(\.$platform) followers in \(.applicationName)",
                "How many \(\.$platform) followers in \(.applicationName)",
                "Show my \(\.$platform) count in \(.applicationName)"
            ],
            shortTitle: "Check followers",
            systemImageName: "person.2.fill"
        )
        AppShortcut(
            intent: OpenCleanupDeckIntent(),
            phrases: [
                "Open \(.applicationName) cleanup",
                "Open my cleanup deck in \(.applicationName)"
            ],
            shortTitle: "Open Cleanup",
            systemImageName: "rectangle.stack.fill"
        )
        AppShortcut(
            intent: GetPlatformStatsIntent(),
            phrases: [
                "Get \(\.$platform) stats in \(.applicationName)",
                "Show \(\.$platform) stats from \(.applicationName)"
            ],
            shortTitle: "Get platform stats",
            systemImageName: "chart.bar.fill"
        )
    }
}
