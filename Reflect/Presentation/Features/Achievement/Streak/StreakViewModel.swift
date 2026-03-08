import Foundation
import SwiftData
import Observation

@Observable
final class StreakViewModel {
    private let getStreakStatsUseCase: GetStreakStatsUseCaseProtocol
    private let calculateStreakUseCase: CalculateStreakUseCaseProtocol
    private let badgeRepository: BadgeRepositoryProtocol

    var streakStats: StreakStats?
    var badges: [Badge] = []
    var isLoading: Bool = false
    var errorMessage: String?

    init(modelContext: ModelContext) {
        // Create repositories directly with the provided modelContext
        let streakRepository = StreakRepository(modelContext: modelContext)
        let reflectionRepository = ReflectionRepository(modelContext: modelContext)
        let badgeRepo = BadgeRepository(modelContext: modelContext)
        let calculationService = StreakCalculationService()

        // Create use cases
        self.getStreakStatsUseCase = GetStreakStatsUseCase(
            streakRepository: streakRepository
        )
        self.calculateStreakUseCase = CalculateStreakUseCase(
            streakRepository: streakRepository,
            reflectionRepository: reflectionRepository,
            calculationService: calculationService
        )
        self.badgeRepository = badgeRepo
    }

    // Keep the original init for DIContainer if needed elsewhere
    init(
        getStreakStatsUseCase: GetStreakStatsUseCaseProtocol,
        calculateStreakUseCase: CalculateStreakUseCaseProtocol,
        badgeRepository: BadgeRepositoryProtocol
    ) {
        self.getStreakStatsUseCase = getStreakStatsUseCase
        self.calculateStreakUseCase = calculateStreakUseCase
        self.badgeRepository = badgeRepository
    }

    func loadStreakStats() async {
        isLoading = true
        errorMessage = nil

        do {
            streakStats = try await getStreakStatsUseCase.execute()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func calculateStreak() async {
        isLoading = true
        errorMessage = nil

        do {
            _ = try await calculateStreakUseCase.execute()
            streakStats = try await getStreakStatsUseCase.execute()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    var streakDisplayText: String {
        guard let stats = streakStats else { return "0-Day Streak" }
        return "\(stats.currentStreak)-Day Streak"
    }

    var longestStreakText: String {
        guard let stats = streakStats else { return "Longest: 0 days" }
        return "Longest: \(stats.longestStreak) days"
    }

    var isStreakActive: Bool {
        guard let stats = streakStats else { return false }
        return stats.isStreakActiveToday
    }

    // MARK: - Badge Loading

    /// Load all badges from repository
    func loadBadges() async {
        isLoading = true
        errorMessage = nil

        do {
            badges = try await badgeRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Refresh both streak stats and badges (call after reflection save)
    func refreshAfterReflection() async {
        isLoading = true
        errorMessage = nil

        do {
            // Load stats and badges in parallel for better performance
            async let stats = getStreakStatsUseCase.execute()
            async let allBadges = badgeRepository.fetchAll()

            streakStats = try await stats
            badges = try await allBadges
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Badge Helpers

    /// Get unlocked badges
    var unlockedBadges: [Badge] {
        badges.filter { $0.isUnlocked }
    }

    /// Get locked badges
    var lockedBadges: [Badge] {
        badges.filter { !$0.isUnlocked }
    }

    /// Get newly unlocked badges (unlocked today)
    var newlyUnlockedBadges: [Badge] {
        badges.filter { $0.isUnlocked && $0.isNew }
    }

    /// Check if any badges were just unlocked
    var hasNewUnlocks: Bool {
        !newlyUnlockedBadges.isEmpty
    }
}
