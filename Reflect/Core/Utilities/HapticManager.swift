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
}
