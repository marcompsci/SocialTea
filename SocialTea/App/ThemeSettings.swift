import SwiftUI
import UIKit

@MainActor
@Observable
final class ThemeSettings {
    var nightMode: Bool = false
    var accentR: Double = 0.07
    var accentG: Double = 0.55
    var accentB: Double = 0.52

    init() {
        nightMode = SyncedPrefs.bool(forKey: "theme.nightMode")
        if SyncedPrefs.object(forKey: "theme.accentR") != nil {
            accentR = SyncedPrefs.double(forKey: "theme.accentR")
            accentG = SyncedPrefs.double(forKey: "theme.accentG")
            accentB = SyncedPrefs.double(forKey: "theme.accentB")
        }
    }

    var accentColor: Color {
        Color(red: accentR, green: accentG, blue: accentB)
    }

    func toggleNightMode() {
        nightMode.toggle()
        SyncedPrefs.set(nightMode, forKey: "theme.nightMode")
    }

    func setAccentColor(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        accentR = Double(r)
        accentG = Double(g)
        accentB = Double(b)
        SyncedPrefs.set(accentR, forKey: "theme.accentR")
        SyncedPrefs.set(accentG, forKey: "theme.accentG")
        SyncedPrefs.set(accentB, forKey: "theme.accentB")
    }

    func resetAccentColor() {
        setAccentColor(Color(red: 0.07, green: 0.55, blue: 0.52))
    }

    var colorScheme: ColorScheme? { nightMode ? .dark : nil }
}
