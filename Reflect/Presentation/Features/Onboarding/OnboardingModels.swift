import SwiftUI

/// One full-screen page of the onboarding pager: a hero glyph, a headline, a short
/// explanation, and a few concrete highlights.
struct OnboardingPage: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    var highlights: [OnboardingHighlight] = []
}

/// A single "here's what you can actually do" line under a page's headline.
struct OnboardingHighlight: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

// MARK: - Content

extension OnboardingPage {
    /// The onboarding script. Ordered: what the app is, then the three things it's built
    /// around — Learnings, Insights, Spaces.
    static let all: [OnboardingPage] = [
        OnboardingPage(
            icon: "book.closed.fill",
            title: "Welcome to Reflect",
            subtitle: "A journal for the things you're learning — and everything in it stays yours.",
            color: .primaryDefault,
            highlights: [
                OnboardingHighlight(icon: "square.and.pencil", text: "Write it, photograph it, or just say it out loud"),
                OnboardingHighlight(icon: "lock.icloud.fill", text: "Kept in your own iCloud, never on our servers"),
                OnboardingHighlight(icon: "hand.raised.fill", text: "No account to create, no ads, no tracking")
            ]
        ),
        OnboardingPage(
            icon: "book.fill",
            title: "Learning Chapters",
            subtitle: "One topic you're working on, holding every reflection you've written about it.",
            color: .primaryDefault,
            highlights: [
                OnboardingHighlight(icon: "folder.fill", text: "Make a topic in a couple of taps"),
                OnboardingHighlight(icon: "mic.fill", text: "Speak Indonesian or English — we'll type it out"),
                OnboardingHighlight(icon: "lock.fill", text: "Notes, photos, and recordings stay in your iCloud")
            ]
        ),
        OnboardingPage(
            icon: "lightbulb.fill",
            title: "Insights",
            subtitle: "A single line you can save in seconds now and make sense of later.",
            color: .warning,
            highlights: [
                OnboardingHighlight(icon: "questionmark.circle.fill", text: "Keep a question you can't answer yet"),
                OnboardingHighlight(icon: "bolt.fill", text: "Add one from the widget or Siri, app closed"),
                OnboardingHighlight(icon: "iphone", text: "Insights never leave your device")
            ]
        ),
        OnboardingPage(
            icon: "person.3.fill",
            title: "Spaces",
            subtitle: "A small, private group you invite people into when you want feedback.",
            color: .success,
            highlights: [
                OnboardingHighlight(icon: "person.badge.plus", text: "Only the people you invite can see it"),
                OnboardingHighlight(icon: "text.bubble.fill", text: "Ask for feedback; replies stay in a thread"),
                OnboardingHighlight(icon: "lock.fill", text: "Never public or searchable — leave any time")
            ]
        )
    ]
}
