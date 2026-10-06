import StoreKit
import SwiftUI

/// SocialTea Pro paywall. Uses Apple's SubscriptionStoreView so the price, renewal terms,
/// restore button and legal links are always shown the way App Review expects.
struct PaywallView: View {
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubscriptionStoreView(productIDs: [SubscriptionManager.productID]) {
            marketing
        }
        .subscriptionStoreButtonLabel(.multiline)
        .storeButton(.visible, for: .restorePurchases)
        .subscriptionStorePolicyDestination(url: SubscriptionManager.termsURL, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: SubscriptionManager.privacyPolicyURL, for: .privacyPolicy)
        .onInAppPurchaseCompletion { [subscriptions] _, result in
            if case .success(.success(let verification)) = result,
               case .verified(let transaction) = verification {
                await transaction.finish()
                await subscriptions.refresh()   // isPro flips → onChange below closes the sheet
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .accessibilityLabel("Close")
        }
        .onChange(of: subscriptions.isPro) { _, isPro in
            if isPro {
                Haptics.success()
                dismiss()
            }
        }
    }

    private var marketing: some View {
        VStack(spacing: 18) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .background(Circle().fill(Theme.gradient))
                .padding(.top, 28)
            VStack(spacing: 6) {
                Text("SocialTea Pro")
                    .font(.largeTitle.weight(.bold))
                Text("See every name, every change.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                feature("person.crop.circle.badge.xmark", "Full lists", "Every name in Not following back, Fans and Mutuals")
                feature("clock.arrow.2.circlepath", "Compare exports", "Unfollowed, New followers and Gone quiet")
                feature("rectangle.stack.fill", "Cleanup mode", "Swipe through who doesn\u{2019}t follow back")
                feature("chart.bar.xaxis", "Insights", "Charts and a shareable stats card")
                feature("square.and.arrow.up", "Export", "Share any list as TXT or CSV")
            }
            .padding(.horizontal, 28)
            Label("Still 100% on your phone. Apple handles the payment.", systemImage: "lock.shield.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 12)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.tea)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Inline upsell shown where a Pro feature would be.
struct ProLockedCard: View {
    let title: String
    let message: String
    @Environment(SubscriptionManager.self) private var subscriptions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(Theme.honey)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                subscriptions.showPaywall = true
            } label: {
                Text("Unlock SocialTea Pro")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.tea)
            Text("Try everything free with demo data on the Dashboard.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))
    }
}
