import StoreKit
import UIKit

/// Requests an App Store review after the user has performed a meaningful number
/// of actions (imports + cleanup decisions). Prompts at most once per app version.
@MainActor
@Observable
final class ReviewManager {
    private static let actionCountKey       = "review.actionCount"
    private static let lastPromptVersionKey = "review.lastPromptVersion"
    private static let threshold            = 3

    private var actionCount: Int

    init() {
        actionCount = UserDefaults.standard.integer(forKey: Self.actionCountKey)
    }

    func recordAction() {
        actionCount += 1
        UserDefaults.standard.set(actionCount, forKey: Self.actionCountKey)
        considerPrompt()
    }

    private func considerPrompt() {
        guard actionCount >= Self.threshold else { return }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let lastPrompted = UserDefaults.standard.string(forKey: Self.lastPromptVersionKey) ?? ""
        guard lastPrompted != version else { return }

        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }

        UserDefaults.standard.set(version, forKey: Self.lastPromptVersionKey)
        SKStoreReviewController.requestReview(in: scene)
    }
}
