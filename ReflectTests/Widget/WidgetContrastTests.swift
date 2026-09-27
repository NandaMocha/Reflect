import Testing
import UIKit
@testable import Reflect

/// WCAG 2.x AA checks for the Quick Actions widget colour tokens: text needs 4.5:1 and icons
/// need 3:1 against both widget surfaces, in light and in dark appearance.
struct WidgetContrastTests {
    private static let styles: [UIUserInterfaceStyle] = [.light, .dark]

    private func resolved(_ token: WidgetPalette.Token, _ style: UIUserInterfaceStyle) -> UIColor {
        WidgetPalette.uiColor(token).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    // MARK: - Contrast helper

    @Test func blackOnWhiteIsTwentyOne() {
        #expect(abs(WidgetPalette.contrastRatio(.black, .white) - 21) < 0.01)
    }

    @Test func whiteOnWhiteIsOne() {
        #expect(abs(WidgetPalette.contrastRatio(.white, .white) - 1) < 0.01)
    }

    @Test func ratioIsSymmetric() {
        let gray = UIColor(white: 0.5, alpha: 1)
        #expect(WidgetPalette.contrastRatio(gray, .white) == WidgetPalette.contrastRatio(.white, gray))
    }

    @Test func midGrayMatchesKnownValue() {
        // sRGB #777777 on white is 4.48:1 (WebAIM contrast checker).
        let gray = UIColor(red: 0x77 / 255, green: 0x77 / 255, blue: 0x77 / 255, alpha: 1)
        #expect(abs(WidgetPalette.contrastRatio(gray, .white) - 4.48) < 0.01)
    }

    // MARK: - Tokens

    @Test(arguments: WidgetPalette.Token.allCases)
    func everyTokenResolvesFromTheAssetCatalog(_ token: WidgetPalette.Token) {
        #expect(UIColor(named: token.rawValue, in: WidgetPalette.bundle, compatibleWith: nil) != nil)
    }

    @Test(arguments: WidgetPalette.textTokens, WidgetPalette.surfaces)
    func textTokenMeetsAAOnSurface(_ text: WidgetPalette.Token, _ surface: WidgetPalette.Token) {
        for style in Self.styles {
            let ratio = WidgetPalette.contrastRatio(resolved(text, style), resolved(surface, style))
            #expect(ratio >= 4.5, "\(text) on \(surface), \(style == .dark ? "dark" : "light"): \(ratio)")
        }
    }

    @Test(arguments: WidgetPalette.iconTokens, WidgetPalette.surfaces)
    func iconTokenMeetsAAOnSurface(_ icon: WidgetPalette.Token, _ surface: WidgetPalette.Token) {
        for style in Self.styles {
            let ratio = WidgetPalette.contrastRatio(resolved(icon, style), resolved(surface, style))
            #expect(ratio >= 3, "\(icon) on \(surface), \(style == .dark ? "dark" : "light"): \(ratio)")
        }
    }

    @Test func everyActionUsesAnIconToken() {
        for action in QuickAction.all {
            #expect(WidgetPalette.iconTokens.contains(action.tint), "\(action.title)")
        }
    }
}
