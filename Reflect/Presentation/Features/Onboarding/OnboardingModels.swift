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
            subtitle: "Your learning journal. Capture what you're learning, revisit it later, and grow with people you trust.",
            color: .primaryDefault,
            highlights: [
                OnboardingHighlight(icon: "square.and.pencil", text: "Write with text, photos, voice notes, or video"),
                OnboardingHighlight(icon: "icloud.fill", text: "Backed up to your own private iCloud"),
                OnboardingHighlight(icon: "widget.small.badge.plus", text: "Capture from the widget, Siri, or Spotlight")
            ]
        ),
        OnboardingPage(
            icon: "book.fill",
            title: "Learnings",
            subtitle: "A Learning is a topic you're working on. Every reflection you write lives inside one, so your progress stays organised.",
            color: .primaryDefault,
            highlights: [
                OnboardingHighlight(icon: "folder.fill", text: "Group reflections by topic — Swift, cooking, anything"),
                OnboardingHighlight(icon: "mic.fill", text: "Dictate in Indonesian or English, get an instant transcript"),
                OnboardingHighlight(icon: "rosette", text: "Unlock badges as your reflections add up")
            ]
        ),
        OnboardingPage(
            icon: "lightbulb.fill",
            title: "Insights",
            subtitle: "For the thoughts that don't need a full reflection yet. Catch them in seconds before they slip away.",
            color: .warning,
            highlights: [
                OnboardingHighlight(icon: "questionmark.circle.fill", text: "Save a question to come back and answer"),
                OnboardingHighlight(icon: "note.text", text: "Or a note you just want to keep close"),
                OnboardingHighlight(icon: "bolt.fill", text: "Add one without even opening the app")
            ]
        ),
        OnboardingPage(
            icon: "person.3.fill",
            title: "Spaces",
            subtitle: "Learning sticks better with feedback. Invite people you trust into a private, invite-only space.",
            color: .success,
            highlights: [
                OnboardingHighlight(icon: "person.badge.plus", text: "Only the people you invite can see it"),
                OnboardingHighlight(icon: "text.bubble.fill", text: "Ask for feedback and talk it through in a thread"),
                OnboardingHighlight(icon: "lock.fill", text: "Leave any time — owners can remove anyone")
            ]
        )
    ]
}
