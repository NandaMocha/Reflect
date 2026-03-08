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
        let previousTotalReflections = streakData.totalReflections

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

        // 1. Streak badges (monthly)
        unlockedBadges.append(contentsOf: badgeEvaluationService.evaluateStreakBadges(
            newStreak: newStreak,
            previousStreak: previousStreak
        ))

        // 2. Reflection milestone badges
        unlockedBadges.append(contentsOf: badgeEvaluationService.evaluateReflectionMilestoneBadges(
            totalReflections: streakData.totalReflections,
            previousTotal: previousTotalReflections
        ))

        // 3. Media milestone badges
        let allReflections = try await reflectionRepository.fetchAll()
        let mediaCount = allReflections.filter { reflection in
            !reflection.images.isEmpty || !reflection.videos.isEmpty
        }.count

        // Note: You may want to store previous media count in streak data for proper comparison
        unlockedBadges.append(contentsOf: badgeEvaluationService.evaluateMediaMilestoneBadges(
            mediaCount: mediaCount,
            previousCount: 0 // TODO: Track previous media count in StreakData
        ))

        // 4. Prompt milestone badges
        // TODO: Implement prompt tracking - currently Reflection model doesn't have prompt field
        // This will be added when the prompt feature is implemented
        // For now, we skip prompt badge evaluation
        // let promptCount = allReflections.filter { reflection in
        //     // Check if reflection was created from a guided prompt
        //     return false // Placeholder until prompt tracking is added
        // }.count
        //
        // unlockedBadges.append(contentsOf: badgeEvaluationService.evaluatePromptMilestoneBadges(
        //     promptCount: promptCount,
        //     previousCount: 0 // TODO: Track previous prompt count in StreakData
        // ))

        // 5. Special achievements
        // Monthly Champion (first month complete)
        if badgeEvaluationService.checkMonthlyChampion(
            totalReflections: streakData.totalReflections,
            hasUnlockedBefore: false // TODO: Check if already unlocked
        ) {
            unlockedBadges.append(.monthlyChampion)
        }

        // Quarterly Champion (90-day consistency)
        if badgeEvaluationService.checkQuarterlyChampion(
            currentStreak: newStreak,
            hasUnlockedBefore: false // TODO: Check if already unlocked
        ) {
            unlockedBadges.append(.quarterlyChampion)
        }

        // Half-Year Hero (180-day consistency)
        if badgeEvaluationService.checkHalfYearHero(
            currentStreak: newStreak,
            hasUnlockedBefore: false // TODO: Check if already unlocked
        ) {
            unlockedBadges.append(.halfYearHero)
        }

        // Get celebration trigger
        let celebrationTrigger = badgeEvaluationService.getCelebrationForStreak(
            newStreak,
            previousStreak: previousStreak
        )

        // Unlock badges
        for badgeID in unlockedBadges {
            if let badge = try await badgeRepository.fetch(id: badgeID.rawValue) {
                // Always unlock monthly streak badges, or unlock once for permanent badges
                if badgeID.badgeType == .monthlyStreak || !badge.isUnlocked {
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
