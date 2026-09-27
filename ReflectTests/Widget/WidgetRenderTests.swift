import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Reflect

/// Renders the Quick Actions widget views outside WidgetKit and checks that nothing overflows
/// the widget's content area.
///
/// Sizes: Apple's HIG does not list the iPhone 17 (402 x 874 pt) screen yet, so these use the
/// 393 x 852 pt row of the HIG widget table (small 158 x 158, medium 338 x 158). A wider screen
/// never gets a smaller widget, so this is the tightest fit the iPhone 17 can show. WidgetKit
/// then insets content by the default 16 pt content margin on each side, which leaves
/// 126 x 126 (small) and 306 x 126 (medium) for the view.
@MainActor
struct WidgetRenderTests {
    nonisolated enum Family: String, CaseIterable, Sendable {
        case small, medium

        var widgetSize: CGSize {
            switch self {
            case .small: CGSize(width: 158, height: 158)
            case .medium: CGSize(width: 338, height: 158)
            }
        }
    }

    nonisolated static let contentMargin: CGFloat = 16

    /// The two quotes that stress the medium layout, by rendered characters (text plus author).
    nonisolated enum QuoteLength: String, CaseIterable, Sendable {
        case shortest, longest
    }

    nonisolated struct RenderCase: Sendable, CustomTestStringConvertible {
        let family: Family
        let dark: Bool
        let dynamicType: DynamicTypeSize
        let quote: QuoteLength

        var testDescription: String {
            "\(family.rawValue), \(dark ? "dark" : "light"), \(dynamicType), \(quote.rawValue) quote"
        }

        var contentSize: CGSize {
            CGSize(width: family.widgetSize.width - 2 * WidgetRenderTests.contentMargin,
                   height: family.widgetSize.height - 2 * WidgetRenderTests.contentMargin)
        }
    }

    static func quote(_ length: QuoteLength) -> DailyQuote {
        let rendered = { (quote: DailyQuote) in quote.text.count + (quote.author?.count ?? 0) }
        let sorted = DailyQuote.all.sorted { rendered($0) < rendered($1) }
        return (length == .shortest ? sorted.first : sorted.last) ?? DailyQuote.forDate(.now)
    }

    nonisolated static let cases: [RenderCase] = Family.allCases.flatMap { family in
        [false, true].flatMap { dark in
            [DynamicTypeSize.large, .accessibility3].flatMap { dynamicType in
                QuoteLength.allCases.map { RenderCase(family: family, dark: dark, dynamicType: dynamicType, quote: $0) }
            }
        }
    }

    private func widget(for renderCase: RenderCase) -> some View {
        let entry = QuickActionsEntry(date: .now, quote: Self.quote(renderCase.quote))
        return Group {
            switch renderCase.family {
            case .small: AnyView(SmallQuickActionsView(entry: entry))
            case .medium: AnyView(MediumQuickActionsView(entry: entry))
            }
        }
        .environment(\.dynamicTypeSize, renderCase.dynamicType)
        .environment(\.colorScheme, renderCase.dark ? .dark : .light)
    }

    @Test func shortestAndLongestQuotesDiffer() {
        #expect(Self.quote(.shortest) != Self.quote(.longest))
    }

    @Test(arguments: cases)
    func fitsInsideTheWidget(_ renderCase: RenderCase) {
        let proposal = renderCase.contentSize
        let host = UIHostingController(rootView: widget(for: renderCase))
        let fitted = host.sizeThatFits(in: proposal)
        #expect(fitted.width <= proposal.width + 0.5, "width \(fitted.width) > \(proposal.width)")
        #expect(fitted.height <= proposal.height + 0.5, "height \(fitted.height) > \(proposal.height)")
    }

    @Test(arguments: cases)
    func rendersAnImage(_ renderCase: RenderCase) throws {
        let size = renderCase.family.widgetSize
        let content = widget(for: renderCase)
            .frame(width: renderCase.contentSize.width, height: renderCase.contentSize.height)
            .padding(Self.contentMargin)
            .frame(width: size.width, height: size.height)
            .background(WidgetPalette.background)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, renderCase.dark ? .dark : .light)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.uiImage)
        #expect(image.size == size)

        let png = try #require(image.pngData())
        let name = "widget-\(renderCase.family.rawValue)-\(renderCase.dark ? "dark" : "light")-\(renderCase.dynamicType)-\(renderCase.quote.rawValue).png"
        Attachment.record(png, named: name)
    }
}
