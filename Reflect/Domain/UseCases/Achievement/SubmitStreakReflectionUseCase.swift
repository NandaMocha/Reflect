import Foundation

struct SubmitStreakReflectionResult {
    let newStreak: Int
    let previousStreak: Int
    let unlockedBadges: [BadgeID]
    let celebrationTrigger: BadgeUnlockEvent.CelebrationTrigger
}

protocol SubmitStreakReflectionUseCaseProtocol {
    func execute(reflection: Reflection) async throws -> SubmitStreakReflectionResult
}

final class SubmitStreakReflectionUseCase: SubmitStreakReflectionUseCaseProtocol {
    private let streakRepository: StreakRepositoryProtocol
    private let reflectionRepository: ReflectionRepositoryProtocol
    private let badgeRepository: BadgeRepositoryProtocol
    private let monthlyAchievementRepository: MonthlyAchievementRepositoryProtocol
    private let calculationService: StreakCalculationService
    private let badgeEvaluationService: BadgeEvaluationService

    init(
        streakRepository: StreakRepositoryProtocol,
        reflectionRepository: ReflectionRepositoryProtocol,
        badgeRepository: BadgeRepositoryProtocol,
        monthlyAchievementRepository: MonthlyAchievementRepositoryProtocol,
        calculationService: StreakCalculationService,
        badgeEvaluationService: BadgeEvaluationService
    ) {
        self.streakRepository = streakRepository
        self.reflectionRepository = reflectionRepository
        self.badgeRepository = badgeRepository
        self.monthlyAchievementRepository = monthlyAchievementRepository
        self.calculationService = calculationService
        self.badgeEvaluationService = badgeEvaluationService
    }

    func execute(reflection: Reflection) async throws -> SubmitStreakReflectionResult {
        // Mark as streak submission
        reflection.submittedDate = Date()
        reflection.isStreakSubmission = true
        try await reflectionRepository.update(reflection)

        // Get previous streak
        let streakData = try await streakRepository.getStreakData()
        let previousStreak = streakData.currentStreak

        // Calculate new streak
        let reflections = try await reflectionRepository.fetchAll()
        let newStreak = calculationService.calculateCurrentStreak(reflections: reflections)

        // Update streak data
        streakData.currentStreak = newStreak
        streakData.lastSubmissionDate = Date()
        streakData.totalReflections += 1

        if newStreak > streakData.longestStreak {
            streakData.longestStreak = newStreak
        }

        if newStreak > 0 && previousStreak == 0 {
            streakData.streakStartDate = Date()
        }

        try await streakRepository.updateStreakData(streakData)

        // Evaluate badges
        var unlockedBadges: [BadgeID] = []

        // Streak badges
        unlockedBadges.append(contentsOf: badgeEvaluationService.evaluateStreakBadges(
            newStreak: newStreak,
            previousStreak: previousStreak
        ))

        // First day of month badge
        if let submittedDate = reflection.submittedDate,
           badgeEvaluationService.checkFirstDayOfMonth(submittedDate: submittedDate) {
            unlockedBadges.append(.firstDayMonth)
        }

        // First reflection badge
        if badgeEvaluationService.checkFirstReflection(totalReflections: streakData.totalReflections) {
            unlockedBadges.append(.firstReflection)
        }

        // Get celebration trigger
        let celebrationTrigger = badgeEvaluationService.getCelebrationForStreak(
            newStreak,
            previousStreak: previousStreak
        )

        // Unlock badges
        for badgeID in unlockedBadges {
            if let badge = try await badgeRepository.fetch(id: badgeID.rawValue) {
                if !badge.isUnlocked {
                    try await badgeRepository.unlock(badge)
                }
            }
        }

        return SubmitStreakReflectionResult(
            newStreak: newStreak,
            previousStreak: previousStreak,
            unlockedBadges: unlockedBadges,
            celebrationTrigger: celebrationTrigger
        )
    }
}
