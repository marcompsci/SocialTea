import SwiftUI

/// Swipe through "Not following back". Swiping left only QUEUES a profile so you can
/// unfollow it yourself in the official app — SocialTea never unfollows anyone.
struct CleanupView: View {
    @Environment(SessionStore.self) private var store
    @Environment(ThemeSettings.self) private var themeSettings
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(ReviewManager.self) private var reviewManager
    @State private var showQueue = false
    @State private var celebrated = false

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
                        withAnimation(.snappy) { store.decide(person, decision, platform: platform) }
                    }
                    .padding(.horizontal, 24)
                    controls(platform: platform, top: deck.first, canUndo: !state.history.isEmpty)
                        .padding(.bottom, 8)
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
                                withAnimation(.snappy) { store.decideAll(.keep, platform: platform) }
                            } label: {
                                Label("Keep all remaining", systemImage: "heart")
                            }
                            Button(role: .destructive) {
                                Haptics.light()
                                withAnimation(.snappy) { store.decideAll(.unfollow, platform: platform) }
                            } label: {
                                Label("Queue all to unfollow", systemImage: "xmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showQueue) {
                UnfollowQueueView(platform: platform)
            }
            .onChange(of: store.selectedPlatform) { _, _ in celebrated = false }
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
            circleButton("xmark", tint: Theme.berry, label: "Queue to unfollow") {
                if let top { Haptics.light(); withAnimation(.snappy) { store.decide(top, .unfollow, platform: platform) } }
            }
            circleButton("arrow.uturn.backward", tint: .secondary, label: "Undo", small: true) {
                Haptics.light()
                withAnimation(.snappy) { _ = store.undo(platform: platform) }
            }
            .disabled(!canUndo)
            .opacity(canUndo ? 1 : 0.4)
            circleButton("heart.fill", tint: Theme.tea, label: "Keep following") {
                if let top { Haptics.light(); withAnimation(.snappy) { store.decide(top, .keep, platform: platform) } }
            }
        }
    }

    private func circleButton(_ symbol: String, tint: Color, label: String, small: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(small ? .title3.weight(.bold) : .title.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: small ? 52 : 68, height: small ? 52 : 68)
                .background(Circle().fill(Color(.secondarySystemGroupedBackground)).shadow(color: .black.opacity(0.08), radius: 8, y: 3))
        }
        .accessibilityLabel(label)
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
    private let threshold: CGFloat = 110

    var body: some View {
        VStack(spacing: 14) {
            InitialAvatar(person: person, size: 96)
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
        .frame(maxWidth: .infinity, minHeight: 340)
        .background(RoundedRectangle(cornerRadius: 28).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(alignment: .topLeading) { stamp("KEEP", Theme.tea, visible: offset.width > 30).padding(20) }
        .overlay(alignment: .topTrailing) { stamp("UNFOLLOW", Theme.berry, visible: offset.width < -30).padding(20) }
        .shadow(color: .black.opacity(isTop ? 0.12 : 0.05), radius: 14, y: 6)
        .scaleEffect(1 - CGFloat(depth) * 0.05)
        .offset(x: offset.width, y: offset.height * 0.2 + CGFloat(depth) * 14)
        .rotationEffect(.degrees(Double(offset.width / 18)))
        .allowsHitTesting(isTop)
        .gesture(drag, including: isTop ? .all : .none)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Keep following") { onDecide(.keep) }
        .accessibilityAction(named: "Queue to unfollow") { onDecide(.unfollow) }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { offset = $0.translation }
            .onEnded { value in
                let dx = value.translation.width + value.predictedEndTranslation.width * 0.2
                if dx > threshold {
                    fling(to: 600, .keep)
                } else if dx < -threshold {
                    fling(to: -600, .unfollow)
                } else {
                    withAnimation(.spring(duration: 0.35, bounce: 0.3)) { offset = .zero }
                }
            }
    }

    private func fling(to x: CGFloat, _ decision: SessionStore.CleanupState.Decision) {
        withAnimation(.easeIn(duration: 0.2)) { offset = CGSize(width: x, height: offset.height) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            onDecide(decision)
        }
    }

    private func stamp(_ text: String, _ color: Color, visible: Bool) -> some View {
        Text(text)
            .font(.headline.weight(.heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 3))
            .rotationEffect(.degrees(text == "KEEP" ? -12 : 12))
            .opacity(visible ? 1 : 0)
    }
}

// MARK: - Completion

private struct CompletionView: View {
    let platform: Platform
    let state: SessionStore.CleanupState
    let total: Int
    let onShowQueue: () -> Void
    let onRestart: () -> Void

    var body: some View {
        ZStack {
            if !state.history.isEmpty {
                ConfettiView()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: total == 0 ? "checkmark.seal.fill" : "party.popper.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.gradient)
                Text(total == 0 ? "Everyone follows you back" : "Deck complete!")
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
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
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
        (0..<80).map { i in
        let colors: [Color] = [Theme.tea, Theme.honey, Theme.berry, .purple, .blue, .yellow]
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
