import Foundation

struct StreakStats {
    let currentStreak: Int
    let longestStreak: Int
    let lastSubmissionDate: Date?
    let streakStartDate: Date?
    let totalReflections: Int
    let isStreakActiveToday: Bool
    let daysUntilNextMilestone: Int?
    let nextMilestoneValue: Int?

    // MARK: - Computed Properties

    var streakPercentageToNext: Double {
        guard let nextMilestone = nextMilestoneValue else { return 1.0 }
        let percentage = Double(currentStreak) / Double(nextMilestone)
        return min(percentage, 1.0)
    }

    var nextMilestoneName: String {
        guard let next = nextMilestoneValue else { return "Ongoing" }
        return "\(next)-Day Streak"
    }

    var isStreakBroken: Bool {
        currentStreak == 0 && totalReflections > 0
    }
}
