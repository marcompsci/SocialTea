import Foundation
import Observation
import StoreKit

/// SocialTea Pro — one auto-renewing subscription at $7.99/month, handled entirely by
/// StoreKit 2. Apple processes the payment; SocialTea has no server and stores nothing.
///
/// Free: import, Dashboard numbers, every list's count, the first few names in each list,
/// the Guide, App Lock, and demo data with everything unlocked.
/// Pro: every name, comparisons (unfollowed / new / gone quiet), Cleanup, Insights, export.
@MainActor
@Observable
final class SubscriptionManager {
    /// Must match the product you create in App Store Connect.
    static let productID = "com.phoronomics.socialtea.pro.monthly"
    /// Names shown per list before the Pro upsell.
    static let freePreviewCount = 5

    static let privacyPolicyURL = URL(string: "https://marcompsci.github.io/SocialTea/privacy")!
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private(set) var isPro = false
    var showPaywall = false

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestPro") { isPro = true }
        #endif
        Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task { [weak self] in await self?.refresh() }
    }

    /// Re-reads the active entitlement from StoreKit (works offline from the on-device receipt).
    func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestPro") { isPro = true; return }
        #endif
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                active = true
            }
        }
        isPro = active
    }

    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }

    /// Demo data is always fully unlocked so anyone (including App Review) can try every feature.
    func isUnlocked(_ data: PlatformData) -> Bool {
        isPro || (data.current?.isDemo ?? false)
    }

    func isUnlocked(platforms: [PlatformData]) -> Bool {
        isPro || (!platforms.isEmpty && platforms.allSatisfy { $0.current?.isDemo ?? false })
    }
}
