import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var store
    @Environment(LockManager.self) private var lock
    @Environment(NotificationManager.self) private var notifications
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false
    @State private var showManageSubscription = false
    @AppStorage(WidgetDataCache.optInKey) private var widgetOptIn = false

    @State private var showPINSetup = false
    @State private var confirmStartOver = false
    @State private var confirmClearAll = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PrivacyPromise()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    if subscriptions.isPro {
                        Label("SocialTea Pro is active", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.tea)
                        Button { showManageSubscription = true } label: {
                            Label("Manage subscription", systemImage: "creditcard")
                        }
                    } else {
                        Button { showPaywall = true } label: {
                            Label("Upgrade to SocialTea Pro", systemImage: "sparkles")
                        }
                        Button { Task { await subscriptions.restore() } } label: {
                            Label("Restore purchases", systemImage: "arrow.clockwise")
                        }
                    }
                } header: {
                    Text("SocialTea Pro")
                } footer: {
                    Text("Every name, snapshot comparisons, Cleanup, Insights and export. Billed monthly through your Apple ID; cancel anytime in Settings.")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { lock.biometricEnabled },
                        set: { newValue in
                            if newValue {
                                Task { _ = await lock.enableBiometrics() }
                            } else {
                                lock.biometricEnabled = false
                            }
                        })) {
                        Label(lock.biometryName, systemImage: "faceid")
                    }
                    .disabled(!lock.biometricsAvailable && !lock.biometricEnabled)

                    if lock.sessionPIN == nil {
                        Button { showPINSetup = true } label: {
                            Label("Set a session PIN", systemImage: "circle.grid.3x3")
                        }
                    } else {
                        Button(role: .destructive) { lock.setPIN(nil) } label: {
                            Label("Remove session PIN", systemImage: "circle.grid.3x3.fill")
                        }
                    }
                } header: {
                    Text("App lock")
                } footer: {
                    Text("Off by default. The lock kicks in when you leave the app. A session PIN is kept in memory and forgotten when the app closes.")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { notifications.enabled },
                        set: { on in
                            if on { Task { await notifications.requestAndEnable() } }
                            else  { notifications.setEnabled(false) }
                        }
                    )) {
                        Label("Check-in reminder", systemImage: "bell.fill")
                    }
                    if notifications.enabled {
                        Picker("Frequency", selection: Binding(
                            get: { notifications.interval },
                            set: { notifications.updateInterval($0) }
                        )) {
                            ForEach(NotificationManager.ReminderInterval.allCases) { interval in
                                Text(interval.rawValue).tag(interval)
                            }
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("A private reminder to download a fresh export and compare it with your last snapshot. Scheduled on your phone — nothing is sent anywhere.")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { widgetOptIn },
                        set: { on in
                            widgetOptIn = on
                            if on { WidgetDataCache.update(from: store) } else { WidgetDataCache.clear() }
                        }
                    )) {
                        Label("Save counts for widget & Siri", systemImage: "square.grid.2x2")
                    }
                } header: {
                    Text("Home Screen & Siri")
                } footer: {
                    Text("Off by default. When on, your latest follower and following totals \u{2014} numbers only, no names \u{2014} are saved on this phone so the widget and Siri can show them. Turn it off to erase them.")
                }

                Section {
                    Button { confirmStartOver = true } label: {
                        Label("Start over", systemImage: "arrow.counterclockwise")
                    }
                    Button(role: .destructive) { confirmClearAll = true } label: {
                        Label("Clear everything for this session", systemImage: "trash")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text(store.hasBundledBaseline
                         ? "Start over wipes every import and restores your labeled baseline snapshot. Clear everything removes the baseline too, until the next launch."
                         : "Start over wipes every import for this session.")
                }

                Section("About") {
                    LabeledContent("Status", value: store.statusLabel)
                    LabeledContent("Network access", value: "None")
                    LabeledContent("Data collected", value: "None")
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    NavigationLink {
                        AppIconExportView()
                    } label: {
                        Label("App Icon Export", systemImage: "app.badge")
                    }
                    Text("SocialTea is a follower tracker for Instagram, Facebook and TikTok exports. It is not affiliated with or endorsed by Instagram, Facebook, TikTok, or Meta.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .manageSubscriptionsSheet(isPresented: $showManageSubscription)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showPINSetup) { PINSetupView() }
            .confirmationDialog("Start over?", isPresented: $confirmStartOver, titleVisibility: .visible) {
                Button("Start over", role: .destructive) { store.startOver(); Haptics.success() }
            } message: {
                Text("All imported lists and demo data are wiped. Your labeled baseline snapshot comes back.")
            }
            .confirmationDialog("Clear everything?", isPresented: $confirmClearAll, titleVisibility: .visible) {
                Button("Clear everything", role: .destructive) { store.clearAll(); Haptics.success() }
            } message: {
                Text("Every list, including the baseline snapshot, is removed for this session.")
            }
        }
    }
}

// MARK: - PIN setup

private struct PINSetupView: View {
    @Environment(LockManager.self) private var lock
    @Environment(\.dismiss) private var dismiss
    @State private var first: String?
    @State private var entry = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Text(first == nil ? "Choose a 4-digit PIN" : "Enter it again")
                    .font(.title3.weight(.semibold))
                PINDots(count: entry.count)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                Spacer()
                PINPad(entry: $entry) { complete($0) }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func complete(_ pin: String) {
        if let first {
            if first == pin {
                lock.setPIN(pin)
                Haptics.success()
                dismiss()
            } else {
                Haptics.warning()
                error = "Those didn't match. Try again."
                self.first = nil
                entry = ""
            }
        } else {
            first = pin
            entry = ""
            error = nil
        }
    }
}
