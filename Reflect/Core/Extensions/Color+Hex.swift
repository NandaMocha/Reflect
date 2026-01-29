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
    // Primary Colors (Muted Green - Main Accent)
    static let primaryLight = Color(hex: "628141")
    static let primaryDefault = Color(hex: "628141")
    static let primaryDark = Color(hex: "40513B")

    // Secondary Colors (Warm Beige & Dark Sage)
    static let secondaryLight = Color(hex: "E5D9B6")
    static let secondaryDefault = Color(hex: "17252A")
    static let secondaryDark = Color(hex: "40513B")

    // Semantic Colors
    static let success = Color(hex: "7BC950")
    static let warning = Color(hex: "FFB74D")
    static let error = Color(hex: "EF6461")
    static let info = Color(hex: "64B5F6")

    // New Palette - Earth Tone Theme
    static let sageDark = Color(hex: "40513B")          // Dark Sage Green
    static let sageMedium = Color(hex: "628141")        // Muted Green (Primary)
    static let beigeLight = Color(hex: "E5D9B6")        // Warm Beige/Cream
    static let orangeWarm = Color(hex: "E67E22")        // Warm Orange (Action/Warning)

    // Learning Category Colors
    static let coral = Color(hex: "FF8A80")
    static let ocean = Color(hex: "80DEEA")
    static let lavender = Color(hex: "B39DDB")
    static let mint = Color(hex: "A5D6A7")
    static let peach = Color(hex: "FFCC80")
    static let sky = Color(hex: "81D4FA")
    static let rose = Color(hex: "F48FB1")
    static let sage = Color(hex: "C5E1A5")

    // Background Colors - Light Mode
    static let backgroundPrimaryLight = Color(hex: "FEFEFE")
    static let backgroundSecondaryLight = Color(hex: "F7F9FA")
    static let backgroundTertiaryLight = Color(hex: "EDF2F4")

    // Background Colors - Dark Mode (Dark Sage)
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
