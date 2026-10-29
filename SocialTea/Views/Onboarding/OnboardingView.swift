import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SessionStore.self) private var store
    @State private var currentPage = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(OnboardingPage.all.indices, id: \.self) { i in
                    OnboardingPageView(page: OnboardingPage.all[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            bottomBar
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                ForEach(OnboardingPage.all.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == currentPage ? Theme.tea : Color.secondary.opacity(0.3))
                        .frame(width: i == currentPage ? 24 : 8, height: 8)
                        .animation(reduceMotion ? nil : Motion.change, value: currentPage)
                }
            }

            if currentPage < OnboardingPage.all.count - 1 {
                Button {
                    withAnimation(reduceMotion ? nil : Motion.change) { currentPage += 1 }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.tea))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.pressable)

                Button("Skip intro") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Button { dismiss() } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.tea))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.pressable)
                Button {
                    for p in Platform.allCases { store.loadDemo(p) }
                    dismiss()
                } label: {
                    Text("Explore with demo data")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.tea.opacity(0.12)))
                        .foregroundStyle(Theme.tea)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 48)
        .padding(.top, 12)
    }
}

// MARK: - Page view

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: page.symbol)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Theme.tea)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text(page.title)
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(page.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
    }
}

// MARK: - Page data

private struct OnboardingPage {
    let symbol: String
    let title: String
    let body: String

    static let all: [OnboardingPage] = [
        .init(
            symbol: "cup.and.saucer",
            title: "See who follows you back",
            body: "SocialTea reads the follower lists Instagram, Facebook and TikTok already let you download, and sorts out who follows back, who doesn't, and who left."
        ),
        .init(
            symbol: "square.and.arrow.down",
            title: "Bring your own file",
            body: "Request your data export in each app, then open it here. SocialTea never asks for a login or a password."
        ),
        .init(
            symbol: "lock",
            title: "It stays on your phone",
            body: "SocialTea has no servers and makes no network requests. Lists are forgotten when you close the app, unless you turn on Remember last snapshot."
        ),
    ]
}
