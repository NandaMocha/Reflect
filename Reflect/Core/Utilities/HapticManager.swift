import UIKit

final class HapticManager {
    static let shared = HapticManager()

    private init() {}

    // MARK: - Impact Feedback

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    func lightImpact() {
        impact(.light)
    }

    func mediumImpact() {
        impact(.medium)
    }

    func heavyImpact() {
        impact(.heavy)
    }

    func softImpact() {
        impact(.soft)
    }

    func rigidImpact() {
        impact(.rigid)
    }

    // MARK: - Notification Feedback

    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    func success() {
        notification(.success)
    }

    func warning() {
        notification(.warning)
    }

    func error() {
        notification(.error)
    }

    // MARK: - Selection Feedback

    func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    // MARK: - Rhythm Patterns

    /// Plays a `. . - .` celebration rhythm (short, short, long, short).
    /// Short = soft tap, long = heavy tap with an extra accent. Timed so the pattern
    /// completes in ~1.1s — long enough to feel intentional, short enough not to lag
    /// the celebration reveal.
    @MainActor
    func playAchievementRhythm() async {
        softImpact()
        try? await Task.sleep(nanoseconds: 220_000_000)
        softImpact()
        try? await Task.sleep(nanoseconds: 220_000_000)
        heavyImpact()
        try? await Task.sleep(nanoseconds: 100_000_000)
        rigidImpact()  // accent for the "long" beat
        try? await Task.sleep(nanoseconds: 300_000_000)
        softImpact()
    }
}
