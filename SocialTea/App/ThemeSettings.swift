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
        nightMode = UserDefaults.standard.bool(forKey: "theme.nightMode")
        if UserDefaults.standard.object(forKey: "theme.accentR") != nil {
            accentR = UserDefaults.standard.double(forKey: "theme.accentR")
            accentG = UserDefaults.standard.double(forKey: "theme.accentG")
            accentB = UserDefaults.standard.double(forKey: "theme.accentB")
        }
    }

    var accentColor: Color {
        Color(red: accentR, green: accentG, blue: accentB)
    }

    func toggleNightMode() {
        nightMode.toggle()
        UserDefaults.standard.set(nightMode, forKey: "theme.nightMode")
    }

    func setAccentColor(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        accentR = Double(r)
        accentG = Double(g)
        accentB = Double(b)
        UserDefaults.standard.set(accentR, forKey: "theme.accentR")
        UserDefaults.standard.set(accentG, forKey: "theme.accentG")
        UserDefaults.standard.set(accentB, forKey: "theme.accentB")
    }

    func resetAccentColor() {
        setAccentColor(Color(red: 0.07, green: 0.55, blue: 0.52))
    }

    var colorScheme: ColorScheme? { nightMode ? .dark : nil }
}
