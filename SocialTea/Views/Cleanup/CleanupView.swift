import ActivityKit
import SwiftUI
import TipKit

/// Swipe through "Not following back". Swiping left only QUEUES a profile so you can
/// unfollow it yourself in the official app — SocialTea never unfollows anyone.
struct CleanupView: View {
    @Environment(SessionStore.self) private var store
    @Environment(ThemeSettings.self) private var themeSettings
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(ReviewManager.self) private var reviewManager
    @State private var showQueue = false
    @State private var celebrated = false
    @State private var cleanupActivity: Activity<CleanupActivityAttributes>?

    private let bulkDecideTip = BulkDecideTip()
    private let keyboardTip   = KeyboardCleanupTip()

    var body: some View {
        @Bindable var store = store
        let platform = store.selectedPlatform
        let deck = store.cleanupDeck(platform)
        let state = store.cleanupState(platform)
        let total = store.result(.notFollowingBack, for: platform)

        NavigationStack {
            VStack(spacing: 16) {
                Picker("Platform", selection: $store.selectedPlatform) {
                    ForEach(Platform.allCases) { p in Text(p.name).tag(p) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if platform.friendsAreMutual {
                    Spacer()
                    NoticeCard(symbol: "person.2", title: "Nothing to clean up on Facebook",
                               message: "Facebook friends are always mutual, so nobody is \"not following back\".")
                        .padding(.horizontal)
                    Spacer()
                } else if total.availability == .ready && !subscriptions.isUnlocked(store.platformData(platform)) {
                    Spacer()
                    ProLockedCard(title: "Cleanup is part of Pro",
                                  message: "Swipe through the \(total.count.formatted()) people who don\u{2019}t follow you back and build your unfollow to-do list.")
                        .padding(.horizontal)
                    Spacer()
                } else if total.availability != .ready {
                    Spacer()
                    unavailable(total, platform: platform)
                        .padding(.horizontal)
                    Spacer()
                } else if deck.isEmpty {
                    CompletionView(platform: platform, state: state, total: total.count,
                                   onShowQueue: { showQueue = true },
                                   onRestart: { store.resetCleanup(platform); celebrated = false })
                        .onAppear {
                            if !celebrated && !state.history.isEmpty {
                                celebrated = true
                                Haptics.success()
                            }
                        }
                } else {
                    progress(done: state.history.count, total: total.count)
                        .padding(.horizontal)
                    SwipeDeck(people: Array(deck.prefix(3)), platform: platform) { person, decision in
                        reviewManager.recordAction()
                        Haptics.light()
                        withAnimation(Motion.change) { store.decide(person, decision, platform: platform) }
                        Task { await KeyboardCleanupTip.cardDecided.donate() }
                    }
                    .padding(.horizontal, 24)
                    TipView(keyboardTip, arrowEdge: .none)
                        .padding(.horizontal)
                    controls(platform: platform, top: deck.first, canUndo: !state.history.isEmpty)
                        .padding(.bottom, 8)
                    // Hardware-keyboard shortcuts for the swipe deck
                    keyboardDeckShortcuts(platform: platform, top: deck.first, canUndo: !state.history.isEmpty)
                }
            }
            .padding(.top, 8)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Cleanup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showQueue = true } label: {
                        Label("Queue (\(state.unfollowQueue.count))", systemImage: "list.bullet.rectangle")
                    }
                    .disabled(state.unfollowQueue.isEmpty)
                }
                if !deck.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button {
                                Haptics.light()
                                withAnimation(Motion.change) { store.decideAll(.keep, platform: platform) }
                            } label: {
                                Label("Keep all remaining", systemImage: "heart")
                            }
                            Button(role: .destructive) {
                                Haptics.light()
                                withAnimation(Motion.change) { store.decideAll(.unfollow, platform: platform) }
                            } label: {
                                Label("Queue all to unfollow", systemImage: "xmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .popoverTip(bulkDecideTip)
                    }
                }
            }
            .sheet(isPresented: $showQueue) {
                UnfollowQueueView(platform: platform)
            }
            .onAppear {
                if !deck.isEmpty { startCleanupActivity(platform: platform, deckCount: deck.count) }
                BulkDecideTip.deckSize = deck.count
            }
            .onChange(of: deck.count) { _, count in BulkDecideTip.deckSize = count }
            .userActivity("com.socialtea.cleanup", isActive: store.selectedTab == .cleanup) { activity in
                activity.title = "Review your cleanup deck in SocialTea"
                activity.isEligibleForSearch = true
                activity.isEligibleForPrediction = true
                activity.suggestedInvocationPhrase = "Open my SocialTea cleanup"
            }
            .onChange(of: state.history.count) { _, _ in
                updateCleanupActivity(platform: store.selectedPlatform)
            }
            .onChange(of: deck.isEmpty) { old, new in
                let p = store.selectedPlatform
                if new {
                    let cs = store.cleanupState(p)
                    endCleanupActivity(kept: cs.keep.count, queued: cs.unfollowQueue.count)
                } else if old {
                    startCleanupActivity(platform: p, deckCount: store.cleanupDeck(p).count)
                }
            }
            .onChange(of: store.selectedPlatform) { _, _ in
                celebrated = false
                Task {
                    await cleanupActivity?.end(
                        .init(state: .init(remaining: 0, kept: 0, queued: 0), staleDate: nil),
                        dismissalPolicy: .immediate
                    )
                    cleanupActivity = nil
                }
            }
        }
    }

    private func startCleanupActivity(platform: Platform, deckCount: Int) {
        guard cleanupActivity == nil,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = CleanupActivityAttributes(platformName: platform.name)
        let cs = store.cleanupState(platform)
        let initState = CleanupActivityAttributes.ContentState(
            remaining: deckCount, kept: cs.keep.count, queued: cs.unfollowQueue.count
        )
        cleanupActivity = try? Activity<CleanupActivityAttributes>.request(
            attributes: attrs,
            content: .init(state: initState, staleDate: nil)
        )
    }

    private func updateCleanupActivity(platform: Platform) {
        let remaining = store.cleanupDeck(platform).count
        let cs = store.cleanupState(platform)
        let newState = CleanupActivityAttributes.ContentState(
            remaining: remaining, kept: cs.keep.count, queued: cs.unfollowQueue.count
        )
        Task { await cleanupActivity?.update(.init(state: newState, staleDate: nil)) }
    }

    private func endCleanupActivity(kept: Int, queued: Int) {
        let finalState = CleanupActivityAttributes.ContentState(remaining: 0, kept: kept, queued: queued)
        Task {
            await cleanupActivity?.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(30))
            )
            cleanupActivity = nil
        }
    }

    private func progress(done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(done) of \(total) reviewed").font(.footnote.weight(.semibold))
                Spacer()
                Text("← Unfollow · Keep →").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(themeSettings.accentColor)
        }
    }

    private func controls(platform: Platform, top: Person?, canUndo: Bool) -> some View {
        HStack(spacing: 28) {
            circleButton("xmark", tint: Theme.berry, label: "Add to unfollow queue",
                         hint: "Queues this person as someone to unfollow in \(platform.name)") {
                if let top { Haptics.light(); withAnimation(Motion.change) { store.decide(top, .unfollow, platform: platform) } }
            }
            circleButton("arrow.uturn.backward", tint: .secondary, label: "Undo last decision",
                         hint: "Brings the previous card back so you can decide again", small: true) {
                Haptics.light()
                withAnimation(Motion.change) { _ = store.undo(platform: platform) }
            }
            .disabled(!canUndo)
            .opacity(canUndo ? 1 : 0.4)
            circleButton("heart.fill", tint: Theme.tea, label: "Keep following",
                         hint: "Marks this person as keep and moves to the next card") {
                if let top { Haptics.light(); withAnimation(Motion.change) { store.decide(top, .keep, platform: platform) } }
            }
        }
    }

    private func keyboardDeckShortcuts(platform: Platform, top: Person?, canUndo: Bool) -> some View {
        Group {
            // Keyboard actions repeat hundreds of times — they apply instantly, no animation.
            Button("Keep") {
                if let top { Haptics.light(); store.decide(top, .keep, platform: platform) }
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            Button("Queue to unfollow") {
                if let top { Haptics.light(); store.decide(top, .unfollow, platform: platform) }
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Undo") {
                Haptics.light(); _ = store.undo(platform: platform)
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!canUndo)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    @ScaledMetric private var controlSize: CGFloat = 68
    @ScaledMetric private var controlSmallSize: CGFloat = 52

    private func circleButton(_ symbol: String, tint: Color, label: String, hint: String = "",
                              small: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(small ? .title3.weight(.bold) : .title.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: small ? controlSmallSize : controlSize,
                       height: small ? controlSmallSize : controlSize)
                .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    @ViewBuilder
    private func unavailable(_ result: ViewResult, platform: Platform) -> some View {
        switch result.availability {
        case .countsOnly:
            NoticeCard(symbol: "number.circle", title: "Names needed",
                       message: "Your \(platform.name) snapshot holds counts only. Import your export (followers + following) to swipe through real names.",
                       tint: Theme.honey)
        case .needsFollowingList:
            NoticeCard(symbol: "doc.badge.plus", title: "Both lists needed",
                       message: "Import both your followers and following lists so SocialTea can find who isn't following back.",
                       tint: Theme.honey)
        default:
            NoticeCard(symbol: "tray", title: "No \(platform.name) lists loaded",
                       message: "Import your export or load demo data from the Dashboard.")
        }
    }
}

// MARK: - Swipe deck

private struct SwipeDeck: View {
    let people: [Person]
    let platform: Platform
    let onDecide: (Person, SessionStore.CleanupState.Decision) -> Void

    var body: some View {
        ZStack {
            ForEach(Array(people.enumerated().reversed()), id: \.element.id) { index, person in
                SwipeCard(person: person, platform: platform, isTop: index == 0, depth: index) { decision in
                    onDecide(person, decision)
                }
            }
        }
        .frame(maxHeight: 420)
    }
}

private struct SwipeCard: View {
    let person: Person
    let platform: Platform
    let isTop: Bool
    let depth: Int
    let onDecide: (SessionStore.CleanupState.Decision) -> Void

    @State private var offset: CGSize = .zero
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric private var avatarSize: CGFloat = 96
    @ScaledMetric private var cardMinHeight: CGFloat = 340
    private let threshold: CGFloat = 110

    var body: some View {
        VStack(spacing: 14) {
            InitialAvatar(person: person, size: avatarSize)
            Text(person.title)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let name = person.displayName, name != person.username {
                Text(name).foregroundStyle(.secondary)
            }
            Text("Doesn't follow you back on \(platform.name)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                if let url = platform.profileURL(for: person) { openURL(url) }
            } label: {
                Label("View profile", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: cardMinHeight)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(alignment: .topLeading) { stamp("KEEP", Theme.tea, amount: offset.width).padding(20) }
        .overlay(alignment: .topTrailing) { stamp("UNFOLLOW", Theme.berry, amount: -offset.width).padding(20) }
        .shadow(color: .black.opacity(isTop ? 0.08 : 0.03), radius: 10, y: 4)
        .scaleEffect(1 - CGFloat(depth) * 0.05)
        .offset(x: offset.width, y: offset.height * 0.2 + CGFloat(depth) * 14)
        .rotationEffect(.degrees(Double(offset.width / 18)))
        .allowsHitTesting(isTop)
        .gesture(drag, including: isTop ? .all : .none)
        .accessibilityLabel("\(person.title)\(person.displayName.map { ", \($0)" } ?? "")")
        .accessibilityValue("Doesn't follow you back on \(platform.name)")
        .accessibilityHint("Swipe up to keep, swipe down to queue to unfollow")
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Keep following") { onDecide(.keep) }
        .accessibilityAction(named: "Queue to unfollow") { onDecide(.unfollow) }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { offset = $0.translation }
            .onEnded { value in
                let dx = value.translation.width
                let vx = value.velocity.width
                // A quick flick is enough — distance OR speed commits the decision.
                if dx > threshold || vx > 700 {
                    fling(.keep, velocity: max(vx, 900))
                } else if dx < -threshold || vx < -700 {
                    fling(.unfollow, velocity: min(vx, -900))
                } else if !reduceMotion {
                    withAnimation(Motion.settle) { offset = .zero }
                } else {
                    offset = .zero
                }
            }
    }

    /// Throws the card off-screen at the finger's own speed, then records the decision.
    /// The deck stays interactive the whole time — no sleep, no lockout.
    private func fling(_ decision: SessionStore.CleanupState.Decision, velocity: CGFloat) {
        guard !reduceMotion else {
            offset = .zero
            onDecide(decision)
            return
        }
        let target = CGSize(width: velocity > 0 ? 700 : -700, height: offset.height)
        let distance = max(abs(target.width - offset.width), 1)
        withAnimation(.interpolatingSpring(stiffness: 260, damping: 32,
                                           initialVelocity: abs(velocity) / distance)) {
            offset = target
        } completion: {
            onDecide(decision)
        }
    }

    /// Stamps fade in with the drag instead of popping on at a threshold, so the card
    /// hints at what letting go will do.
    private func stamp(_ text: String, _ color: Color, amount: CGFloat) -> some View {
        Text(text)
            .font(.headline.weight(.heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).stroke(color, lineWidth: 2.5))
            .rotationEffect(.degrees(text == "KEEP" ? -10 : 10))
            .opacity(Double(min(max((amount - 16) / 80, 0), 1)))
    }
}

// MARK: - Completion

private struct CompletionView: View {
    let platform: Platform
    let state: SessionStore.CleanupState
    let total: Int
    let onShowQueue: () -> Void
    let onRestart: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !state.history.isEmpty && !reduceMotion {
                ConfettiView()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.tea)
                Text(total == 0 ? "Everyone follows you back" : "All reviewed")
                    .font(.title2.weight(.bold))
                if total > 0 {
                    HStack(spacing: 14) {
                        summaryTile(state.keep.count, "Kept", Theme.tea)
                        summaryTile(state.unfollowQueue.count, "To unfollow", Theme.berry)
                    }
                    .padding(.horizontal)
                    Text("Your unfollow queue is a to-do list. Open each profile and unfollow in \(platform.name) — SocialTea doesn't touch your account.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    HStack {
                        Button(action: onShowQueue) { Label("Open queue", systemImage: "list.bullet") }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.berry)
                            .disabled(state.unfollowQueue.isEmpty)
                        Button(action: onRestart) { Label("Start again", systemImage: "arrow.counterclockwise") }
                            .buttonStyle(.bordered)
                    }
                }
                Spacer()
            }
        }
    }

    private func summaryTile(_ value: Int, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            AnimatedCounter(value: value).foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Color(.secondarySystemGroupedBackground)))
    }
}

// MARK: - Unfollow queue

struct UnfollowQueueView: View {
    let platform: Platform
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: ShareItem?

    var body: some View {
        let queue = store.cleanupState(platform).unfollowQueue
        NavigationStack {
            List {
                Section {
                    ForEach(queue) { person in
                        PersonRow(person: person, platform: platform, view: .notFollowingBack)
                    }
                } footer: {
                    Text("Tap a name to open it in \(platform.name), then unfollow there. This queue disappears when you close the app.")
                }
            }
            .overlay {
                if queue.isEmpty {
                    ContentUnavailableView("Queue is empty", systemImage: "tray",
                                           description: Text("Swipe left on a card to add someone."))
                }
            }
            .navigationTitle("Unfollow queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(ExportBuilder.Format.allCases) { format in
                            Button("Share as \(format.title)") {
                                let text = ExportBuilder.text(for: queue, platform: platform, format: format)
                                shareItem = ExportFile.make(text: text,
                                                            fileName: ExportBuilder.fileName(platform: platform, view: "unfollow queue", format: format))
                            }
                        }
                    } label: { Image(systemName: "square.and.arrow.up") }
                    .disabled(queue.isEmpty)
                }
            }
            .sheet(item: $shareItem) { item in ActivityView(item: item).presentationDetents([.medium, .large]) }
        }
    }
}

// MARK: - Confetti

struct ConfettiView: View {
    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat
        let delay: Double
        let speed: Double
        let spin: Double
        let color: Color
        let size: CGFloat
    }

    @State private var start = Date()
    @State private var pieces: [Piece] = ConfettiView.makePieces()

    private static func makePieces() -> [Piece] {
        (0..<44).map { i in
        let colors: [Color] = [Theme.tea, Theme.honey, Theme.berry]
        return Piece(id: i,
                     x: CGFloat.random(in: 0...1),
                     delay: Double.random(in: 0...0.8),
                     speed: Double.random(in: 0.35...0.7),
                     spin: Double.random(in: -6...6),
                     color: colors[i % colors.count],
                     size: CGFloat.random(in: 6...11))
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                for p in pieces {
                    let local = t - p.delay
                    guard local > 0 else { continue }
                    let y = CGFloat(local * p.speed) * size.height - 20
                    guard y < size.height + 20 else { continue }
                    let x = p.x * size.width + CGFloat(sin(local * 3 + Double(p.id))) * 18
                    var ctx = context
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .radians(local * p.spin))
                    ctx.fill(Path(CGRect(x: -p.size / 2, y: -p.size / 4, width: p.size, height: p.size / 2)),
                             with: .color(p.color))
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { start = Date() }
        .accessibilityHidden(true)
    }
}
