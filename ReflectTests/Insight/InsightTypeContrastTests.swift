import SwiftUI
import Testing
import UIKit
@testable import Reflect

/// WCAG 2.x AA checks for the insight type tag colours. The tag pill (`EntryCard.tagPill`) draws
/// caption2 text in the type colour on a capsule filled with the same colour at 18% opacity, so
/// the text has to reach 4.5:1 against that tint, on every surface the pill sits on, in light
/// and in dark appearance.
struct InsightTypeContrastTests {
    private static let pillFillOpacity: CGFloat = 0.18
    /// Selected type chip in the Insight editor: same colour on a 20% fill.
    private static let chipFillOpacity: CGFloat = 0.2
    private static let schemes: [ColorScheme] = [.light, .dark]

    /// Surfaces the pill sits on: the `glassCard` fill of `EntryCard`, plus the system
    /// backgrounds as a proxy for sheets and lists.
    private func surfaces(_ scheme: ColorScheme) -> [(name: String, color: UIColor)] {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let card = UIColor(scheme == .dark ? Color.backgroundSecondaryDark : Color.backgroundSecondaryLight)
        var result: [(name: String, color: UIColor)] = [
            ("glassCard", card),
            ("systemBackground", UIColor.systemBackground.resolvedColor(with: traits))
        ]
        if scheme == .dark {
            result.append(("black", .black))
            result.append(("secondarySystemBackground", UIColor.secondarySystemBackground.resolvedColor(with: traits)))
        }
        return result
    }

    private func tagColor(_ type: InsightType, _ scheme: ColorScheme) -> UIColor {
        UIColor(Color(hex: type.colorHex(for: scheme)))
    }

    /// `foreground` drawn at `opacity` over an opaque `background`.
    private func composite(_ foreground: UIColor, opacity: CGFloat, over background: UIColor) -> UIColor {
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        foreground.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        background.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        func mix(_ front: CGFloat, _ back: CGFloat) -> CGFloat { front * opacity + back * (1 - opacity) }
        return UIColor(red: mix(fr, br), green: mix(fg, bg), blue: mix(fb, bb), alpha: 1)
    }

    private func label(_ scheme: ColorScheme) -> String { scheme == .dark ? "dark" : "light" }

    // MARK: - Colour pair

    @Test(arguments: InsightType.allCases)
    func lightAndDarkUseDifferentHex(_ type: InsightType) {
        #expect(type.colorHex(for: .light) != type.colorHex(for: .dark))
    }

    @Test(arguments: InsightType.allCases, schemes)
    func hexIsSixDigitsWithoutHash(_ type: InsightType, _ scheme: ColorScheme) {
        let hex = type.colorHex(for: scheme)
        let isHex = hex.allSatisfy { $0.isHexDigit }
        #expect(hex.count == 6)
        #expect(isHex, "\(hex)")
    }

    // MARK: - Contrast

    @Test(arguments: InsightType.allCases, schemes)
    func tagPillTextMeetsAA(_ type: InsightType, _ scheme: ColorScheme) {
        let text = tagColor(type, scheme)
        for surface in surfaces(scheme) {
            let fill = composite(text, opacity: Self.pillFillOpacity, over: surface.color)
            let ratio = WidgetPalette.contrastRatio(text, fill)
            #expect(ratio >= 4.5, "\(type) pill on \(surface.name), \(label(scheme)): \(ratio)")
        }
    }

    @Test(arguments: InsightType.allCases, schemes)
    func selectedEditorChipMeetsAA(_ type: InsightType, _ scheme: ColorScheme) {
        let text = tagColor(type, scheme)
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let sheets = [UIColor.systemBackground, .secondarySystemBackground].map { $0.resolvedColor(with: traits) }
        for sheet in sheets {
            let fill = composite(text, opacity: Self.chipFillOpacity, over: sheet)
            let ratio = WidgetPalette.contrastRatio(text, fill)
            #expect(ratio >= 4.5, "\(type) chip, \(label(scheme)): \(ratio)")
        }
    }
}
