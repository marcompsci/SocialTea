import AppIntents

struct SocialTeaFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "SocialTea"

    @Parameter(title: "Hide cleanup badge", default: false)
    var suppressBadge: Bool

    @Parameter(title: "Silence digest notifications", default: false)
    var silentDigest: Bool

    var displayRepresentation: DisplayRepresentation {
        .init(title: "SocialTea")
    }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(suppressBadge, forKey: "focus.suppressBadge")
        UserDefaults.standard.set(silentDigest, forKey: "focus.silentDigest")
        return .result()
    }
}
