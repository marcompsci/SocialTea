import SwiftUI

/// Full-screen lock shown when the optional app lock is on.
struct LockView: View {
    @Environment(LockManager.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @State private var entry = ""
    @State private var failed = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.gradient)
            Text("SocialTea is locked").font(.title2.weight(.bold))

            if lock.sessionPIN != nil {
                PINDots(count: entry.count)
                    .modifier(Shake(trigger: failed))
                Text("Enter your session PIN").font(.footnote).foregroundStyle(.secondary)
            }
            if let error = lock.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            Spacer()
            if lock.sessionPIN != nil {
                PINPad(entry: $entry) { pin in
                    if !lock.unlock(withPIN: pin) {
                        Haptics.warning()
                        withAnimation(.default) { failed.toggle() }
                        entry = ""
                    }
                }
            }
            if lock.biometricEnabled || lock.sessionPIN == nil {
                Button {
                    Task { await lock.unlockWithBiometrics() }
                } label: {
                    Label("Unlock with \(lock.biometryName)", systemImage: "faceid")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.tea)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThickMaterial)
        .task {
            // Only prompt while the app is in front; a prompt started in the background fails.
            if lock.biometricEnabled && scenePhase == .active { await lock.unlockWithBiometrics() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && lock.biometricEnabled && lock.isLocked {
                Task { await lock.unlockWithBiometrics() }
            }
        }
    }
}

struct PINDots: View {
    let count: Int
    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .strokeBorder(Theme.tea, lineWidth: 2)
                    .background(Circle().fill(i < count ? Theme.tea : Color.clear))
                    .frame(width: 16, height: 16)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) of 4 digits entered")
    }
}

struct PINPad: View {
    @Binding var entry: String
    let onComplete: (String) -> Void

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 18), count: 3), spacing: 14) {
            ForEach(keys, id: \.self) { key in
                if key.isEmpty {
                    Color.clear.frame(height: 64)
                } else {
                    Button { tap(key) } label: {
                        Text(key)
                            .font(.title.weight(.medium))
                            .frame(width: 72, height: 64)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(key == "⌫" ? "Delete" : key)
                }
            }
        }
    }

    private func tap(_ key: String) {
        Haptics.light()
        if key == "⌫" {
            if !entry.isEmpty { entry.removeLast() }
            return
        }
        guard entry.count < 4 else { return }
        entry.append(key)
        if entry.count == 4 { onComplete(entry) }
    }
}

private struct Shake: GeometryEffect {
    var trigger: Bool
    var animatableData: CGFloat

    init(trigger: Bool) {
        self.trigger = trigger
        self.animatableData = trigger ? 1 : 0
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}
