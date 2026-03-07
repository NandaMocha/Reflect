import Foundation
import SwiftData

@Model
final class StreakData {
    @Attribute(.unique) var id: UUID = UUID()

    // Current streak tracking
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastSubmissionDate: Date?
    var streakStartDate: Date?

    // Metadata
    var totalReflections: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init() {}

    // MARK: - Helper Methods

    var isStreakActive: Bool {
        guard let lastDate = lastSubmissionDate else { return false }
        let daysSinceLastSubmission = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: lastDate),
            to: Calendar.current.startOfDay(for: .now)
        ).day ?? 0
        return daysSinceLastSubmission <= 1
    }

    var daysUntilMilestone: Int? {
        let milestones = [3, 7, 14, 30]
        for milestone in milestones {
            if currentStreak < milestone {
                return milestone - currentStreak
            }
        }
        return nil
    }
}
