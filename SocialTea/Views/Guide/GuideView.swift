import SwiftUI

/// "How does this work?" — written so a 10-year-old could follow it.
struct GuideView: View {
    @State private var platform: Platform = .instagram

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    warning
                    stepsSection
                    viewsSection
                    privacySection
                    faqSection
                    Text("SocialTea is not made by, endorsed by, or connected to Instagram, Facebook, TikTok, or Meta. Those names belong to their owners.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Guide")
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 36))
                .foregroundStyle(.white)
            Text("How does this work?")
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
            Text("Instagram, Facebook and TikTok will give you a copy of your own lists. You hand that copy to SocialTea, and it does the math right here on your phone.")
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).fill(Theme.gradient))
    }

    private var warning: some View {
        NoticeCard(symbol: "exclamationmark.shield.fill",
                   title: "Never type your password into a follower-tracker",
                   message: "Sites and apps that ask for your login to \"see who unfollowed you\" can get your account locked or stolen. SocialTea never asks for a password — you only ever give it the file the app itself gave you.",
                   tint: .red)
    }

    // MARK: Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("1. Get your file", "square.and.arrow.down.on.square")
            Picker("Platform", selection: $platform) {
                ForEach(Platform.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps(for: platform).enumerated()), id: \.offset) { index, step in
                    StepRow(number: index + 1, text: step, tint: Theme.color(for: platform))
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))

            sectionTitle("2. Give it to SocialTea", "doc.badge.plus")
            card("On the Dashboard, tap **Import** on the right platform. Pick your followers file, then your following file. That's it — the numbers appear instantly.\n\nWant to see who left? Do it again in a few weeks and import the new file as the **newer snapshot**.")
        }
    }

    private func steps(for platform: Platform) -> [String] {
        switch platform {
        case .instagram:
            return [
                "Open Instagram and go to your profile.",
                "Tap ☰, then **Accounts Centre**.",
                "Tap **Your information and permissions** → **Download your information**.",
                "Choose **Some of your information** → **Followers and following**.",
                "Pick **Download to device**, format **JSON**, date range **All time**.",
                "When Instagram says it's ready (can take a while), download the zip.",
                "In the Files app, tap the zip to open it. You want **followers_1.json** and **following.json**."
            ]
        case .facebook:
            return [
                "Open Facebook and go to **Settings & privacy** → **Settings**.",
                "Tap **Accounts Centre** → **Your information and permissions**.",
                "Tap **Download your information** → **Some of your information** → **Friends**.",
                "Pick **Download to device** and format **JSON**.",
                "Download the zip when it's ready and tap it in Files to open it.",
                "You want **your_friends.json** (sometimes called friends.json)."
            ]
        case .tiktok:
            return [
                "Open TikTok and go to your profile.",
                "Tap ☰ → **Settings and privacy** → **Account**.",
                "Tap **Download your data**, choose **JSON**, then **Request data**.",
                "Come back later to the **Download data** tab and download it.",
                "Open the zip in Files. Use **user_data.json** for both lists — SocialTea finds the right part."
            ]
        }
    }

    // MARK: Views

    private var viewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("3. What the lists mean", "list.bullet.rectangle")
            VStack(spacing: 0) {
                ForEach(RelationshipView.allCases) { view in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: view.symbol)
                            .font(.title3)
                            .foregroundStyle(Theme.color(for: view))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(view.title(for: .instagram)).font(.subheadline.weight(.semibold))
                            Text(kidExplanation(view)).font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    if view != RelationshipView.allCases.last { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
            card("**Facebook is different:** friends always go both ways, so everyone shows up under Friends and \"Not following back\" is always 0.")
        }
    }

    private func kidExplanation(_ view: RelationshipView) -> String {
        switch view {
        case .notFollowingBack: return "You follow them, but they don't follow you."
        case .fans: return "They follow you, but you don't follow them."
        case .mutuals: return "You follow each other. Besties!"
        case .unfollowed: return "They followed you in your old file, but not in your new one. Needs two files."
        case .newFollowers: return "They're in your new file but weren't in the old one. Needs two files."
        case .goneQuiet: return "They disappeared from all your lists. Maybe they blocked you, maybe they deleted their account, maybe they took a break — the app can't tell which, so it never says \"blocked\" for sure."
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("4. Our promise", "lock.shield")
            VStack(alignment: .leading, spacing: 10) {
                promise("iphone", "Everything happens on your phone.")
                promise("icloud.slash", "Nothing is uploaded or sent anywhere. Ever.")
                promise("externaldrive.badge.xmark", "Nothing is saved. Close the app and your lists are gone.")
                promise("key.slash", "No logins, no passwords, no accounts.")
                promise("hand.raised", "SocialTea never follows, unfollows, or blocks anyone. Buttons just open the profile so you can do it yourself in the real app.")
                promise("square.and.arrow.up", "If you tap Share, you choose where your file goes — that's you saving your own file.")
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Questions", "questionmark.bubble")
            VStack(spacing: 8) {
                faq("Why doesn't it just log in and check for me?",
                    "Because that means giving away your password and breaking the platforms' rules — accounts get banned for it. Your official export is safe and 100% yours.")
                faq("Why do I need to import again to see unfollowers?",
                    "SocialTea doesn't keep anything, so it can only compare two files you give it: an older one and a newer one.")
                faq("Can it tell me who blocked me?",
                    "No app can know that for sure. \"Gone quiet\" only shows people who vanished from both of your lists, which could mean a block, a deleted account, or something else.")
                faq("The numbers are a little different from the app.",
                    "Exports are a snapshot from the moment you requested them, and deactivated accounts may be left out. Small differences are normal.")
            }
        }
    }

    // MARK: Helpers

    private func sectionTitle(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.title3.weight(.bold))
    }

    private func card(_ markdown: String) -> some View {
        Text(LocalizedStringKey(markdown))
            .font(.subheadline)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func promise(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.tea).frame(width: 24)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func faq(_ q: String, _ a: String) -> some View {
        DisclosureGroup {
            Text(a).font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } label: {
            Text(q).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }
}

private struct StepRow: View {
    let number: Int
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tint))
            Text(LocalizedStringKey(text))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
