import Foundation
import Testing
@testable import Reflect

struct WidgetDeepLinkTests {
    @Test(arguments: [
        (WidgetDeepLink.write, "reflect://write"),
        (.camera, "reflect://camera"),
        (.voice, "reflect://voice"),
        (.insight, "reflect://insight")
    ])
    func buildsExpectedURL(link: WidgetDeepLink, expected: String) {
        #expect(link.url.absoluteString == expected)
    }

    @Test func expectedURLsCoverEveryCase() {
        #expect(WidgetDeepLink.allCases.count == 4)
    }

    @Test(arguments: WidgetDeepLink.allCases)
    func roundTripsThroughURL(link: WidgetDeepLink) {
        #expect(WidgetDeepLink(url: link.url) == link)
    }

    @Test(arguments: [
        "https://write",
        "reflect://",
        "reflect:",
        "reflect://unknown",
        "write"
    ])
    func rejectsForeignOrUnknownURLs(string: String) throws {
        let url = try #require(URL(string: string))
        #expect(WidgetDeepLink(url: url) == nil)
    }

    /// URL schemes and hosts are case-insensitive (RFC 3986), and iOS opens the app for
    /// `REFLECT://write`, so the parser accepts any casing instead of dropping the tap.
    @Test func acceptsSchemeAndHostInAnyCase() throws {
        let upperScheme = try #require(URL(string: "REFLECT://write"))
        let upperHost = try #require(URL(string: "reflect://WRITE"))
        #expect(WidgetDeepLink(url: upperScheme) == .write)
        #expect(WidgetDeepLink(url: upperHost) == .write)
    }

    // MARK: - App-side mapping

    @Test(arguments: [
        (WidgetDeepLink.write, WidgetAction.write),
        (.camera, .camera),
        (.voice, .voice),
        (.insight, .insight)
    ])
    func mapsDeepLinkToWidgetAction(link: WidgetDeepLink, expected: WidgetAction) {
        #expect(WidgetAction(link) == expected)
    }

    @Test func mappingCoversEveryDeepLinkWithADistinctAction() {
        let actions = WidgetDeepLink.allCases.map { WidgetAction($0) }
        #expect(Set(actions).count == WidgetDeepLink.allCases.count)
    }

    @Test(arguments: WidgetDeepLink.allCases)
    func resolvesActionFromEveryWidgetURL(link: WidgetDeepLink) {
        #expect(WidgetAction(url: link.url) == WidgetAction(link))
    }

    @Test func unknownURLResolvesToNoAction() throws {
        let url = try #require(URL(string: "https://example.com/write"))
        #expect(WidgetAction(url: url) == nil)
    }
}
