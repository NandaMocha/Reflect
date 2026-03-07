import Foundation

protocol GetStreakStatsUseCaseProtocol {
    func execute() async throws -> StreakStats
}

final class GetStreakStatsUseCase: GetStreakStatsUseCaseProtocol {
    private let streakRepository: StreakRepositoryProtocol

    init(streakRepository: StreakRepositoryProtocol) {
        self.streakRepository = streakRepository
    }

    func execute() async throws -> StreakStats {
        let streakData = try await streakRepository.getStreakData()

        let milestones = [3, 7, 14, 30]
        var nextMilestone: Int? = nil

        for milestone in milestones {
            if streakData.currentStreak < milestone {
                nextMilestone = milestone
                break
            }
        }

        return StreakStats(
            currentStreak: streakData.currentStreak,
            longestStreak: streakData.longestStreak,
            lastSubmissionDate: streakData.lastSubmissionDate,
            streakStartDate: streakData.streakStartDate,
            totalReflections: streakData.totalReflections,
            isStreakActiveToday: streakData.isStreakActive,
            daysUntilNextMilestone: nextMilestone.map { $0 - streakData.currentStreak },
            nextMilestoneValue: nextMilestone
        )
    }
}
