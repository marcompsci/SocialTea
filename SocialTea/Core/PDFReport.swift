import UIKit
import SwiftUI
import Charts

enum PDFReport {
    struct PlatformStats {
        let name: String
        let followers: Int
        let following: Int
        let followBackRatio: Double
        let notFollowingBack: Int?
        let isMutual: Bool
    }

    @MainActor
    static func make(platforms: [PlatformStats]) -> Data {
        let pageWidth: CGFloat = 595   // A4 at 72 dpi
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 52
        let contentWidth = pageWidth - margin * 2

        let teal = UIColor(red: 0.07, green: 0.55, blue: 0.52, alpha: 1)

        // Pre-render chart image so it's available inside the synchronous PDF closure
        let chartImg = chartImage(platforms: platforms)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        return renderer.pdfData { ctx in
            ctx.beginPage()
            var y = margin

            // ── Header ──────────────────────────────────────────────────────
            let appName = NSAttributedString(string: "SocialTea", attributes: [
                .font: UIFont.systemFont(ofSize: 26, weight: .bold),
                .foregroundColor: teal
            ])
            appName.draw(at: CGPoint(x: margin, y: y))
            y += 34

            let subtitle = NSAttributedString(string: "Follower Report", attributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: UIColor.secondaryLabel
            ])
            subtitle.draw(at: CGPoint(x: margin, y: y))

            let dateStr = Date().formatted(.dateTime.day().month(.wide).year())
            let dateAS = NSAttributedString(string: dateStr, attributes: [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.secondaryLabel
            ])
            let dateSize = dateAS.size()
            dateAS.draw(at: CGPoint(x: pageWidth - margin - dateSize.width, y: y + 1))
            y += 26

            // Separator
            let sep = UIBezierPath()
            sep.move(to: CGPoint(x: margin, y: y))
            sep.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            sep.lineWidth = 0.5
            teal.withAlphaComponent(0.4).setStroke()
            sep.stroke()
            y += 22

            // ── Follower bar chart ───────────────────────────────────────────
            if let img = chartImg {
                let aspect   = img.size.height / img.size.width
                let imgW     = contentWidth
                let imgH     = imgW * aspect
                img.draw(in: CGRect(x: margin, y: y, width: imgW, height: imgH))
                y += imgH + 18
            }

            // ── Platform sections ────────────────────────────────────────────
            for platform in platforms {
                // Background card
                let cardHeight: CGFloat = platform.isMutual ? 70 : (platform.notFollowingBack != nil ? 108 : 90)
                let cardRect = CGRect(x: margin, y: y, width: contentWidth, height: cardHeight)
                let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 10)
                UIColor.secondarySystemBackground.setFill()
                cardPath.fill()

                // Platform name
                let nameAS = NSAttributedString(string: platform.name, attributes: [
                    .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                    .foregroundColor: UIColor.label
                ])
                nameAS.draw(at: CGPoint(x: margin + 16, y: y + 14))

                // Stats
                let followersNoun = platform.isMutual ? "friends" : "followers"
                let statsLine = "\(platform.followers.formatted()) \(followersNoun)  ·  \(platform.following.formatted()) following"
                let statsAS = NSAttributedString(string: statsLine, attributes: [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.secondaryLabel
                ])
                statsAS.draw(at: CGPoint(x: margin + 16, y: y + 36))

                var subY = y + 54
                if !platform.isMutual {
                    let ratio = Int((platform.followBackRatio * 100).rounded())
                    let ratioLine = "\(ratio)% follow back"
                    let ratioAS = NSAttributedString(string: ratioLine, attributes: [
                        .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                        .foregroundColor: teal
                    ])
                    ratioAS.draw(at: CGPoint(x: margin + 16, y: subY))
                    subY += 18

                    if let nfb = platform.notFollowingBack {
                        let nfbLine = "\(nfb.formatted()) not following back"
                        let nfbAS = NSAttributedString(string: nfbLine, attributes: [
                            .font: UIFont.systemFont(ofSize: 12),
                            .foregroundColor: UIColor.secondaryLabel
                        ])
                        nfbAS.draw(at: CGPoint(x: margin + 16, y: subY))
                    }
                }

                y += cardHeight + 12
            }

            y += 10

            // ── Footer ───────────────────────────────────────────────────────
            let footerY = pageHeight - margin - 14
            let footerAS = NSAttributedString(
                string: "Analyzed privately on-device · SocialTea · No data was shared or uploaded.",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 9),
                    .foregroundColor: UIColor.tertiaryLabel
                ]
            )
            footerAS.draw(with: CGRect(x: margin, y: footerY, width: contentWidth, height: 20),
                          options: .usesLineFragmentOrigin, context: nil)
        }
    }

    // MARK: -

    @MainActor
    private static func chartImage(platforms: [PlatformStats]) -> UIImage? {
        guard !platforms.isEmpty else { return nil }
        let view = PDFBarChart(platforms: platforms)
            .colorScheme(.light)
            .frame(width: 491, height: 120)
        let r = ImageRenderer(content: view)
        r.scale = 2
        return r.uiImage
    }
}

// MARK: - Chart view for PDF embed

private struct PDFBarChart: View {
    let platforms: [PDFReport.PlatformStats]

    var body: some View {
        Chart {
            ForEach(Array(platforms.enumerated()), id: \.offset) { _, p in
                BarMark(
                    x: .value("Platform", p.name),
                    y: .value("Followers", p.followers)
                )
                .foregroundStyle(platformColor(p.name).gradient)
                .cornerRadius(7)
                .annotation(position: .top, alignment: .center) {
                    Text(p.followers.formatted())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 120)
        .padding(.top, 4)
    }

    private func platformColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "instagram": return Color(red: 0.84, green: 0.27, blue: 0.53)
        case "facebook":  return Color(red: 0.23, green: 0.45, blue: 0.86)
        case "tiktok":    return Color(red: 0.12, green: 0.70, blue: 0.72)
        default:          return Color(red: 0.07, green: 0.55, blue: 0.52)
        }
    }
}
