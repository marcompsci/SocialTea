import SwiftUI
import UIKit

// MARK: - Theme

enum Theme {
    static let tea = Color(red: 0.07, green: 0.55, blue: 0.52)      // teal
    static let honey = Color(red: 0.96, green: 0.65, blue: 0.20)    // amber
    static let berry = Color(red: 0.89, green: 0.29, blue: 0.42)
    static let gradient = LinearGradient(colors: [tea, Color(red: 0.16, green: 0.42, blue: 0.62)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)

    static func color(for platform: Platform) -> Color {
        switch platform {
        case .instagram: return Color(red: 0.84, green: 0.27, blue: 0.53)
        case .facebook: return Color(red: 0.23, green: 0.45, blue: 0.86)
        case .tiktok: return Color(red: 0.12, green: 0.70, blue: 0.72)
        }
    }

    static func color(for view: RelationshipView) -> Color {
        switch view {
        case .notFollowingBack: return berry
        case .fans: return honey
        case .mutuals: return tea
        case .unfollowed: return .red
        case .newFollowers: return .green
        case .goneQuiet: return .gray
        }
    }
}

// MARK: - Haptics

@MainActor
enum Haptics {
    static func light() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        g.impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - Avatar

struct InitialAvatar: View {
    let person: Person
    var size: CGFloat = 40

    private var hue: Double {
        let sum = person.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Double(sum % 360) / 360
    }

    var body: some View {
        Text(person.initial)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle().fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.85),
                                                      Color(hue: hue, saturation: 0.7, brightness: 0.6)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Person row

struct PersonRow: View {
    let person: Person
    let platform: Platform
    let view: RelationshipView
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            InitialAvatar(person: person)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if let name = person.displayName, name != person.username {
                    Text(name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                } else if let date = person.date {
                    Text("Since \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            actionButton
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens their profile in the official app")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var actionButton: some View {
        let label: String? = {
            if platform.friendsAreMutual { return nil }
            switch view {
            case .notFollowingBack: return "Unfollow"
            case .fans: return "Follow back"
            case .goneQuiet: return "Check"
            default: return nil
            }
        }()
        Menu {
            if let label {
                Button { open() } label: { Label("\(label) in \(platform.name)", systemImage: "arrow.up.right.square") }
            }
            Button { open() } label: { Label("Open profile", systemImage: "person.crop.circle") }
            Button(role: .destructive) { open() } label: { Label("Block in \(platform.name)", systemImage: "hand.raised") }
            Button { UIPasteboard.general.string = person.username } label: { Label("Copy username", systemImage: "doc.on.doc") }
            ShareLink(item: person, preview: SharePreview(person.title, image: Image(systemName: "person.circle"))) {
                Label("Share handle", systemImage: "square.and.arrow.up")
            }
        } label: {
            Text(label ?? "Open")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
        .accessibilityLabel("Actions for \(person.title)")
    }

    /// Every action just opens the profile; the user finishes it in the official app.
    private func open() {
        Haptics.light()
        if let url = platform.profileURL(for: person) { openURL(url) }
    }
}

// MARK: - Animated counter

struct AnimatedCounter: View {
    let value: Int
    var font: Font = .system(size: 34, weight: .bold, design: .rounded)
    @State private var shown: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(shown, format: .number)
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(shown)))
            .onAppear { animate(to: value) }
            .onChange(of: value) { _, new in animate(to: new) }
    }

    private func animate(to target: Int) {
        if reduceMotion {
            shown = target
        } else {
            withAnimation(.spring(duration: 0.9, bounce: 0.15)) { shown = target }
        }
    }
}

// MARK: - Ratio ring

struct RatioRing: View {
    let ratio: Double
    var lineWidth: CGFloat = 14
    var tint: Color = Theme.tea
    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AngularGradient(colors: [tint.opacity(0.6), tint], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((ratio * 100).rounded()))%")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
                Text("follow back").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 1.1)) { progress = ratio } }
        .onChange(of: ratio) { _, new in withAnimation(.easeOut(duration: 0.8)) { progress = new } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Follow-back ratio \(Int((ratio * 100).rounded())) percent")
    }
}

// MARK: - Privacy promise

struct PrivacyPromise: View {
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(compact ? .body : .title3)
                .foregroundStyle(Theme.tea)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your data stays on your phone")
                    .font(compact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
                Text("SocialTea does not save, collect, or send your data. No logins, no passwords. Close the app and your imported lists are gone.")
                    .font(compact ? .caption : .footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.tea.opacity(0.08)))
    }
}

// MARK: - Share sheet (UIActivityViewController)

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let item: ShareItem

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: [item.url], applicationActivities: nil)
        let url = item.url
        vc.completionWithItemsHandler = { _, _, _, _ in
            // The temporary copy only existed to hand to the Share Sheet.
            try? FileManager.default.removeItem(at: url)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum ExportFile {
    /// Writes a short-lived temp file for the Share Sheet. It is deleted when sharing ends,
    /// and the temp directory is cleared on launch as a backstop.
    static func make(text: String, fileName: String) -> ShareItem? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return ShareItem(url: url)
        } catch {
            return nil
        }
    }

    static func makeData(_ data: Data, fileName: String) -> ShareItem? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return ShareItem(url: url)
        } catch {
            return nil
        }
    }

    static func purge() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: - Shimmer placeholder row

/// Placeholder shown while a list is about to be populated. Uses SwiftUI's built-in
/// `.redacted(reason:)` shimmer rather than a custom animation to stay system-consistent.
struct ShimmerRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).frame(width: 130, height: 12)
                RoundedRectangle(cornerRadius: 4).frame(width: 85, height: 10)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 12).frame(width: 52, height: 26)
        }
        .padding(.vertical, 4)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Small pieces

struct PlatformBadge: View {
    let platform: Platform
    var body: some View {
        Image(systemName: platform.symbol)
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.color(for: platform).gradient))
            .accessibilityHidden(true)
    }
}

struct NoticeCard: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }
}
