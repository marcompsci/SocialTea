import TipKit
import SwiftUI

// Keyboard shortcuts in the Cleanup swipe deck.
struct KeyboardCleanupTip: Tip {
    var title: LocalizedStringResource { "Keyboard shortcuts" }
    var message: LocalizedStringResource? { "← unfollow  ·  → keep  ·  ⌘Z undo — works with any external keyboard too." }
    var image: Image? { Image(systemName: "keyboard") }

    static let cardDecided = Event(id: "socialtea.tip.cardDecided")

    var rules: [Rule] {
        #Rule(Self.cardDecided) { $0.donations.count >= 3 }
    }

    var options: [TipOption] { [Tips.MaxDisplayCount(1)] }
}

// Bulk-decide menu (keep all / queue all) in the Cleanup toolbar.
struct BulkDecideTip: Tip {
    var title: LocalizedStringResource { "Decide all at once" }
    var message: LocalizedStringResource? { "Tap ··· to keep every remaining card — or queue them all to unfollow in one go." }
    var image: Image? { Image(systemName: "ellipsis.circle") }

    @Parameter static var deckSize: Int = 0

    var rules: [Rule] {
        #Rule(Self.deckSize) { $0 > 3 }
    }

    var options: [TipOption] { [Tips.MaxDisplayCount(1)] }
}

// Trend chart in Insights — shown once the chart first appears.
struct TrendChartTip: Tip {
    var title: LocalizedStringResource { "Your follower trend" }
    var message: LocalizedStringResource? { "Grows with each import session. Export the full history as CSV from the report menu." }
    var image: Image? { Image(systemName: "chart.line.uptrend.xyaxis") }

    @Parameter static var isVisible: Bool = false

    var rules: [Rule] {
        #Rule(Self.isVisible) { $0 == true }
    }

    var options: [TipOption] { [Tips.MaxDisplayCount(1)] }
}

// Share card button in the Insights toolbar.
struct ShareCardTip: Tip {
    var title: LocalizedStringResource { "Share your stats" }
    var message: LocalizedStringResource? { "Tap ↑ to generate a polished stats card — privacy-safe, no names included." }
    var image: Image? { Image(systemName: "square.and.arrow.up") }

    static let insightsOpened = Event(id: "socialtea.tip.insightsOpened")

    var rules: [Rule] {
        #Rule(Self.insightsOpened) { $0.donations.count >= 1 }
    }

    var options: [TipOption] { [Tips.MaxDisplayCount(1)] }
}
