import Foundation

/// Parses and routes `socialtea://` deep links.
///
/// Supported URLs:
///   socialtea://platform/instagram          → Lists tab, Instagram
///   socialtea://platform/instagram/cleanup  → Cleanup tab, Instagram
///   socialtea://platform/facebook           → Lists tab, Facebook
///   socialtea://platform/tiktok             → Lists tab, TikTok
///   socialtea://insights                    → Insights tab
///   socialtea://dashboard                   → Dashboard tab
enum DeepLink {
    case openPlatform(Platform)
    case openCleanup(Platform)
    case insights
    case dashboard

    init?(url: URL) {
        guard url.scheme?.lowercased() == "socialtea" else { return nil }
        let host = url.host?.lowercased() ?? ""
        let parts = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }

        switch host {
        case "platform":
            guard let raw = parts.first, let platform = Platform(rawValue: raw) else { return nil }
            if parts.count > 1 && parts[1] == "cleanup" {
                self = .openCleanup(platform)
            } else {
                self = .openPlatform(platform)
            }
        case "insights":
            self = .insights
        case "dashboard":
            self = .dashboard
        default:
            return nil
        }
    }

    @MainActor
    func handle(store: SessionStore) {
        switch self {
        case .openPlatform(let p):
            store.selectedPlatform = p
            store.selectedTab = .lists
        case .openCleanup(let p):
            store.selectedPlatform = p
            store.selectedTab = .cleanup
        case .insights:
            store.selectedTab = .insights
        case .dashboard:
            store.selectedTab = .dashboard
        }
    }
}
