import SwiftUI
import UIKit

/// Colour tokens for the Quick Actions widget, backed by `WidgetColors.xcassets` (compiled into
/// both the app and the widget extension), plus the WCAG contrast helper the tests use to keep
/// every token readable on both widget surfaces.
nonisolated enum WidgetPalette {
    enum Token: String, CaseIterable, Sendable {
        case background = "WidgetBackground"
        case cardSurface = "WidgetCardSurface"
        case textPrimary = "WidgetTextPrimary"
        case textSecondary = "WidgetTextSecondary"
        case actionWrite = "WidgetActionWrite"
        case actionPhoto = "WidgetActionPhoto"
        case actionVoice = "WidgetActionVoice"
        case actionInsight = "WidgetActionInsight"
    }

    /// Surfaces that text and icons sit on.
    static let surfaces: [Token] = [.background, .cardSurface]
    /// Tokens used for text. Must reach 4.5:1 on every surface.
    static let textTokens: [Token] = [.textPrimary, .textSecondary]
    /// Tokens used for icons. Must reach 3:1 on every surface.
    static let iconTokens: [Token] = [.actionWrite, .actionPhoto, .actionVoice, .actionInsight]

    private final class BundleToken {}

    /// The bundle holding the asset catalog: the app or the widget extension, whichever runs.
    static var bundle: Bundle { Bundle(for: BundleToken.self) }

    static func color(_ token: Token) -> Color {
        Color(token.rawValue, bundle: bundle)
    }

    /// Dynamic `UIColor` for `token`. Resolve it with a trait collection to get one appearance.
    static func uiColor(_ token: Token) -> UIColor {
        UIColor(named: token.rawValue, in: bundle, compatibleWith: nil) ?? .clear
    }

    static var background: Color { color(.background) }
    static var cardSurface: Color { color(.cardSurface) }
    static var textPrimary: Color { color(.textPrimary) }
    static var textSecondary: Color { color(.textSecondary) }

    // MARK: - WCAG contrast

    /// WCAG 2.x contrast ratio between two opaque colours, from 1 (same) to 21 (black on white).
    static func contrastRatio(_ first: UIColor, _ second: UIColor) -> Double {
        let lighter = max(relativeLuminance(first), relativeLuminance(second))
        let darker = min(relativeLuminance(first), relativeLuminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// WCAG 2.x relative luminance of an sRGB colour.
    static func relativeLuminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ channel: CGFloat) -> Double {
            let value = Double(min(max(channel, 0), 1))
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
