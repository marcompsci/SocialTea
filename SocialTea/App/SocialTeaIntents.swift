import AppIntents

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

    @Parameter(title: "Platform")
    var platform: PlatformAppEnum

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: WidgetDataCache.suiteName) ?? .standard
        defaults.set(platform.rawValue, forKey: "intent.openPlatform")
        return .result()
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
    }
}
