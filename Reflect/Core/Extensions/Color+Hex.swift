import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String {
        guard let components = UIColor(self).cgColor.components else {
            return "#000000"
        }

        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - App Color Palette (Earth-Tone Theme)
extension Color {
    // The palette is backed by the adaptive color sets in Assets.xcassets/Colors, so each
    // token resolves to its light or dark value automatically. Call sites are unchanged —
    // `Color.primaryDefault` (or the generated `Color(.primaryDefault)`) now adapts on its own.

    // Primary Colors (Muted Green - Main Accent)
    static let primaryLight = Color(.primaryLight)
    static let primaryDefault = Color(.primaryDefault)
    static let primaryDark = Color(.primaryDark)

    // Secondary Colors (Warm Beige & Dark Sage)
    static let secondaryLight = Color(.secondaryLight)
    static let secondaryDefault = Color(.secondaryDefault)
    static let secondaryDark = Color(.secondaryDark)

    // Semantic Colors
    static let success = Color(.success)
    static let warning = Color(.warning)
    static let error = Color(.error)
    static let info = Color(.info)

    // Earth Tone Theme
    static let sageDark = Color(.sageDark)              // Dark Sage Green
    static let sageMedium = Color(.sageMedium)          // Muted Green (Primary)
    static let beigeLight = Color(.beigeLight)          // Warm Beige/Cream
    static let orangeWarm = Color(.orangeWarm)          // Warm Orange (Action/Warning)

    // Learning Category Colors
    static let coral = Color(.coral)
    static let ocean = Color(.ocean)
    static let lavender = Color(.lavender)
    static let mint = Color(.mint)
    static let peach = Color(.peach)
    static let sky = Color(.sky)
    static let rose = Color(.rose)
    static let sage = Color(.sage)

    // Adaptive background surfaces (single token; light/dark resolved from the catalog)
    static let backgroundPrimary = Color(.backgroundPrimary)
    static let backgroundSecondary = Color(.backgroundSecondary)
    static let backgroundTertiary = Color(.backgroundTertiary)

    // Explicit light/dark background values — kept for any manual color-scheme switching.
    static let backgroundPrimaryLight = Color(hex: "FEFEFE")
    static let backgroundSecondaryLight = Color(hex: "F7F9FA")
    static let backgroundTertiaryLight = Color(hex: "EDF2F4")
    static let backgroundPrimaryDark = Color(hex: "40513B")
    static let backgroundSecondaryDark = Color(hex: "3D4C37")
    static let backgroundTertiaryDark = Color(hex: "34422F")

    // Category color array for picker
    static let categoryColors: [Color] = [
        .coral, .ocean, .lavender, .mint, .peach, .sky, .rose, .sage
    ]

    static let categoryColorHexes: [String] = [
        "FF8A80", "80DEEA", "B39DDB", "A5D6A7", "FFCC80", "81D4FA", "F48FB1", "C5E1A5"
    ]
}
