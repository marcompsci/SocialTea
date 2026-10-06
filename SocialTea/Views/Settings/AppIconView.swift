import SwiftUI

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
