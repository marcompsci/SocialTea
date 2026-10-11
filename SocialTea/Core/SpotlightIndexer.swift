import CoreSpotlight
import UniformTypeIdentifiers
import Foundation

@MainActor
struct SpotlightIndexer {
    private static let domainID = "com.socialtea.platforms"

    /// Spotlight is part of the opt-in "Save counts for widget, Siri & Spotlight" setting.
    /// Only totals are indexed — never names.
    static func reindex(using store: SessionStore) {
        guard WidgetDataCache.isEnabled, !store.loadedPlatforms.isEmpty else {
            CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainID])
            return
        }
        let items: [CSSearchableItem] = store.loadedPlatforms.map { platform in
            let stats = store.stats(platform)
            let attr = CSSearchableItemAttributeSet(contentType: UTType.item)
            attr.title = "\(platform.name) on SocialTea"
            attr.contentDescription = "\(stats.followers.formatted()) followers · \(stats.following.formatted()) following"
            attr.keywords = [platform.name, "followers", "following"]
            let item = CSSearchableItem(
                uniqueIdentifier: "socialtea.platform.\(platform.rawValue)",
                domainIdentifier: domainID,
                attributeSet: attr
            )
            item.expirationDate = .distantFuture
            return item
        }
        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
    }

    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainID])
    }
}
