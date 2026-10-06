import SwiftUI
import UIKit

// MARK: - Alternate icon variants

enum AltIcon: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case dark     = "Dark"
    case berry    = "Berry"
    case slate    = "Slate"

    var id: String { rawValue }

    /// Matches the CFBundleAlternateIcons key registered in the app's Info.plist.
    /// nil restores the primary icon.
    var iconName: String? { self == .standard ? nil : "AppIcon-\(rawValue)" }

    var gradient: LinearGradient {
        switch self {
        case .standard:
            return LinearGradient(
                stops: [.init(color: Color(red:0.07,green:0.58,blue:0.54),location:0),
                        .init(color: Color(red:0.09,green:0.35,blue:0.64),location:1)],
                startPoint:.topLeading, endPoint:.bottomTrailing)
        case .dark:
            return LinearGradient(
                stops: [.init(color: Color(red:0.08,green:0.08,blue:0.10),location:0),
                        .init(color: Color(red:0.15,green:0.18,blue:0.24),location:1)],
                startPoint:.topLeading, endPoint:.bottomTrailing)
        case .berry:
            return LinearGradient(
                stops: [.init(color: Color(red:0.82,green:0.18,blue:0.38),location:0),
                        .init(color: Color(red:0.52,green:0.08,blue:0.62),location:1)],
                startPoint:.topLeading, endPoint:.bottomTrailing)
        case .slate:
            return LinearGradient(
                stops: [.init(color: Color(red:0.25,green:0.32,blue:0.46),location:0),
                        .init(color: Color(red:0.15,green:0.19,blue:0.28),location:1)],
                startPoint:.topLeading, endPoint:.bottomTrailing)
        }
    }

    var accentColor: Color {
        switch self {
        case .standard: return Color(red:0.07,green:0.58,blue:0.54)
        case .dark:     return Color(red:0.18,green:0.72,blue:0.68)
        case .berry:    return Color(red:0.82,green:0.18,blue:0.38)
        case .slate:    return Color(red:0.55,green:0.68,blue:0.88)
        }
    }
}

// MARK: - Alternate icon picker

struct AlternateIconPickerView: View {
    @State private var current: String? = UIApplication.shared.alternateIconName
    @State private var isChanging = false
    private let isSupported = UIApplication.shared.supportsAlternateIcons

    var body: some View {
        List {
            if !isSupported {
                Section {
                    Label {
                        Text("Alternate icons are available in the App Store build. Each variant uses the same cup design on a different background — Dark, Berry, and Slate will appear here once the app is live.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2),
                    spacing: 16
                ) {
                    ForEach(AltIcon.allCases) { icon in
                        iconTile(icon)
                    }
                }
                .padding(.vertical, 8)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Choose your icon")
            } footer: {
                // Custom Info.plist registration note for developers
                Text("To enable alternate icons: add CFBundleAlternateIcons to your Info.plist with keys AppIcon-Dark, AppIcon-Berry, and AppIcon-Slate, each pointing to the matching 1024×1024 PNG files in your bundle.")
            }

            Section {
                NavigationLink {
                    AppIconExportView()
                } label: {
                    Label("Export for App Store Connect", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Developer tools")
            }
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isChanging)
        .onAppear { current = UIApplication.shared.alternateIconName }
    }

    private func iconTile(_ icon: AltIcon) -> some View {
        let isSelected = (icon == .standard && current == nil) || (icon.iconName == current)
        return VStack(spacing: 8) {
            ZStack {
                icon.gradient
                RadialGradient(
                    gradient: Gradient(colors: [.white.opacity(0.15), .clear]),
                    center: .center, startRadius: 0, endRadius: 36)
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? icon.accentColor : Color.clear, lineWidth: 3)
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, icon.accentColor)
                        .font(.subheadline.weight(.bold))
                        .offset(x: 5, y: 5)
                }
            }
            .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
            .animation(.spring(duration: 0.25), value: isSelected)

            Text(icon.rawValue)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? icon.accentColor : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { applyIcon(icon) }
        .accessibilityLabel(icon.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @MainActor
    private func applyIcon(_ icon: AltIcon) {
        guard isSupported else { return }
        isChanging = true
        UIApplication.shared.setAlternateIconName(icon.iconName) { _ in
            Task { @MainActor in
                current = UIApplication.shared.alternateIconName
                Haptics.light()
                isChanging = false
            }
        }
    }
}

// MARK: - App icon design

/// The canonical SocialTea icon design — use this as the source of truth when
/// generating the App Store 1024×1024 PNG.
struct AppIconView: View {
    var size: CGFloat = 1024

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.07, green: 0.58, blue: 0.54), location: 0.0),
                    .init(color: Color(red: 0.09, green: 0.35, blue: 0.64), location: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Radial glow behind the cup
            RadialGradient(
                gradient: Gradient(colors: [.white.opacity(0.20), .clear]),
                center: UnitPoint(x: 0.5, y: 0.46),
                startRadius: 0,
                endRadius: size * 0.44
            )

            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: size * 0.44))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.22), radius: size * 0.03, y: size * 0.025)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Icon export tool

/// Accessible from Settings → About → Export App Icon.
/// Renders a 1024×1024 PNG via ImageRenderer and shares it via the system
/// share sheet — paste it straight into App Store Connect.
struct AppIconExportView: View {
    @State private var shareItem: ShareItem?
    @State private var isGenerating = false

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    AppIconView(size: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 26))
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .padding(.vertical, 8)
            }

            Section {
                Button {
                    exportIcon(size: 1024, name: "SocialTea-AppIcon-1024.png")
                } label: {
                    Label(isGenerating ? "Generating…" : "Export 1024×1024 PNG", systemImage: "square.and.arrow.up")
                }
                .disabled(isGenerating)

                Button {
                    exportIcon(size: 180, name: "SocialTea-AppIcon-180.png")
                } label: {
                    Label("Export 180×180 (iPhone @3×)", systemImage: "iphone")
                }
                .disabled(isGenerating)
            } header: {
                Text("Export")
            } footer: {
                Text("The 1024×1024 export is required for App Store Connect. Xcode generates all other sizes from it automatically when you use an \"App Icon\" image set.")
            }

            Section("Preview sizes") {
                HStack(spacing: 16) {
                    ForEach([60, 40, 29], id: \.self) { pts in
                        VStack(spacing: 4) {
                            AppIconView(size: CGFloat(pts * 3))
                                .clipShape(RoundedRectangle(cornerRadius: CGFloat(pts * 3) * 0.22))
                                .frame(width: CGFloat(pts), height: CGFloat(pts))
                            Text("\(pts)pt").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shareItem) { ActivityView(item: $0) }
    }

    @MainActor
    private func exportIcon(size: CGFloat, name: String) {
        isGenerating = true
        defer { isGenerating = false }
        let view = AppIconView(size: size).frame(width: size, height: size)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        guard let image = renderer.uiImage,
              let png = image.pngData(),
              let item = ExportFile.makeData(png, fileName: name) else { return }
        shareItem = item
    }
}
