import Foundation
import Testing
@testable import Reflect

struct OnboardingPageTests {
    @Test func onboardingHasFivePages() {
        #expect(OnboardingPage.all.count == 5)
    }

    @Test func pagesAreInTheExpectedOrder() {
        #expect(OnboardingPage.all.map(\.title) == [
            "Welcome to Reflect",
            "Learning Chapters",
            "Insights",
            "Achievements",
            "Spaces"
        ])
    }

    @Test func achievementsPageHasThreeHighlights() throws {
        let page = try #require(OnboardingPage.all.first { $0.title == "Achievements" })
        #expect(page.icon == "medal.fill")
        #expect(page.highlights.count == 3)
    }

    @Test func spacesPageExplainsFeedbackFirstRule() throws {
        let page = try #require(OnboardingPage.all.first { $0.title == "Spaces" })
        #expect(page.highlights.contains { $0.text.localizedCaseInsensitiveContains("feedback first") })
        #expect((3...4).contains(page.highlights.count))
    }
}
