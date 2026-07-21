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
            subtitle: "Reflect is a journal for the things you're learning. Write something down while it's fresh, then come back later and see how far you've come.",
            color: .primaryDefault,
            highlights: [
                OnboardingHighlight(icon: "square.and.pencil", text: "Capture it as text, a photo, a voice note, or a video — whatever's quickest right then"),
                OnboardingHighlight(icon: "icloud.fill", text: "Everything saves to your private iCloud on its own, so it's waiting on your other devices"),
                OnboardingHighlight(icon: "widget.small.badge.plus", text: "Start one from the widget, Siri, or Spotlight without opening the app first")
            ]
        ),
        OnboardingPage(
            icon: "book.fill",
            title: "Learnings",
            subtitle: "A Learning is one topic you're working on — a language, a course, a new skill. Every reflection you write goes inside one, so everything on that topic stays together.",
            color: .primaryDefault,
            highlights: [
                OnboardingHighlight(icon: "folder.fill", text: "Make a Learning in a couple of taps, then add to it whenever you like"),
                OnboardingHighlight(icon: "mic.fill", text: "Don't feel like typing? Speak in Indonesian or English and we'll write out the transcript"),
                OnboardingHighlight(icon: "rosette", text: "Badges unlock on their own as your reflections add up — nothing to set up")
            ]
        ),
        OnboardingPage(
            icon: "lightbulb.fill",
            title: "Insights",
            subtitle: "Not every thought needs a full reflection. An Insight is a single line you can save in seconds and make sense of later.",
            color: .warning,
            highlights: [
                OnboardingHighlight(icon: "questionmark.circle.fill", text: "Save a question you can't answer yet and return to it when you can"),
                OnboardingHighlight(icon: "note.text", text: "Or keep a note — a term, a link, something someone said in passing"),
                OnboardingHighlight(icon: "bolt.fill", text: "Add one from the widget or Siri, so it's down before you forget it")
            ]
        ),
        OnboardingPage(
            icon: "person.3.fill",
            title: "Spaces",
            subtitle: "A Space is a small private group you invite people into. Share what you're working on and hear back from people who actually know you.",
            color: .success,
            highlights: [
                OnboardingHighlight(icon: "person.badge.plus", text: "Invite only the people you choose — a Space is never public or searchable"),
                OnboardingHighlight(icon: "text.bubble.fill", text: "Post what you'd like feedback on; replies stay in a thread underneath"),
                OnboardingHighlight(icon: "lock.fill", text: "Leave any time, and the owner can remove anyone or close the Space")
            ]
        )
    ]
}
