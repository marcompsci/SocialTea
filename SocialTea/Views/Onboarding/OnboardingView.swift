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
                        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: currentPage)
                }
            }

            if currentPage < OnboardingPage.all.count - 1 {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.4)) { currentPage += 1 }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Theme.tea))
                        .foregroundStyle(.white)
                }

                Button("Skip intro") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Button { dismiss() } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Theme.tea))
                        .foregroundStyle(.white)
                }
                Button {
                    for p in Platform.allCases { store.loadDemo(p) }
                    dismiss()
                } label: {
                    Text("Explore with demo data")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Theme.tea.opacity(0.12)))
                        .foregroundStyle(Theme.tea)
                }
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
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(page.gradient)
                    .frame(width: 140, height: 140)
                    .shadow(color: .black.opacity(0.12), radius: 24, y: 12)
                Image(systemName: page.symbol)
                    .font(.system(size: 58))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 14) {
                Text(page.title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(page.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 36)
            Spacer()
            Spacer()
        }
    }
}

// MARK: - Page data

private struct OnboardingPage {
    let symbol: String
    let gradient: LinearGradient
    let title: String
    let body: String

    static let all: [OnboardingPage] = [
        .init(
            symbol: "cup.and.saucer.fill",
            gradient: LinearGradient(
                colors: [Theme.tea, Color(red: 0.16, green: 0.42, blue: 0.62)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            title: "Welcome to SocialTea",
            body: "Your private, all-in-one follower tracker for Instagram, Facebook, and TikTok."
        ),
        .init(
            symbol: "square.and.arrow.down.fill",
            gradient: LinearGradient(
                colors: [Color(red: 0.23, green: 0.45, blue: 0.86), Color(red: 0.12, green: 0.70, blue: 0.72)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            title: "Import your export",
            body: "Download your official data export from each platform and drop it here. No logins, no passwords — ever."
        ),
        .init(
            symbol: "lock.shield.fill",
            gradient: LinearGradient(
                colors: [Color(red: 0.18, green: 0.65, blue: 0.40), Color(red: 0.07, green: 0.55, blue: 0.52)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            title: "100% on-device",
            body: "Your data never leaves your phone. SocialTea has no network access and collects absolutely nothing."
        ),
        .init(
            symbol: "paintpalette.fill",
            gradient: LinearGradient(
                colors: [Color(red: 0.58, green: 0.27, blue: 0.80), Color(red: 0.89, green: 0.29, blue: 0.42)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            title: "Make it yours",
            body: "Pick a theme color, flip on night mode, and customize the dashboard to your taste."
        ),
    ]
}
