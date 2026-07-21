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
            subtitle: "A simple place to keep what you're learning.",
            color: .primaryDefault,
            highlights: [
                OnboardingHighlight(icon: "square.and.pencil", text: "Write it, photograph it, or just say it"),
                OnboardingHighlight(icon: "icloud.fill", text: "Saved to your own iCloud, on its own"),
                OnboardingHighlight(icon: "widget.small.badge.plus", text: "Start from the widget, Siri, or Spotlight")
            ]
        ),
        OnboardingPage(
            icon: "book.fill",
            title: "Learnings",
            subtitle: "One topic, and everything you've written about it.",
            color: .primaryDefault,
            highlights: [
                OnboardingHighlight(icon: "folder.fill", text: "Add a topic in two taps"),
                OnboardingHighlight(icon: "mic.fill", text: "Speak Indonesian or English — we'll type it out"),
                OnboardingHighlight(icon: "rosette", text: "Badges arrive on their own as you write")
            ]
        ),
        OnboardingPage(
            icon: "lightbulb.fill",
            title: "Insights",
            subtitle: "For a quick thought you don't want to lose.",
            color: .warning,
            highlights: [
                OnboardingHighlight(icon: "questionmark.circle.fill", text: "Keep a question for later"),
                OnboardingHighlight(icon: "note.text", text: "Or a note, in one line"),
                OnboardingHighlight(icon: "bolt.fill", text: "Add one without opening the app")
            ]
        ),
        OnboardingPage(
            icon: "person.3.fill",
            title: "Spaces",
            subtitle: "Share what you're learning with a few people you trust.",
            color: .success,
            highlights: [
                OnboardingHighlight(icon: "person.badge.plus", text: "Send an invite — only they can see it"),
                OnboardingHighlight(icon: "text.bubble.fill", text: "Ask for feedback, reply in a thread"),
                OnboardingHighlight(icon: "lock.fill", text: "Leave whenever you want")
            ]
        )
    ]
}
