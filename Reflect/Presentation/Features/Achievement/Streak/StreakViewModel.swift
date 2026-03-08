import Foundation
import SwiftData
import Observation

@Observable
final class StreakViewModel {
    private let getStreakStatsUseCase: GetStreakStatsUseCaseProtocol
    private let calculateStreakUseCase: CalculateStreakUseCaseProtocol

    var streakStats: StreakStats?
    var isLoading: Bool = false
    var errorMessage: String?

    init(modelContext: ModelContext) {
        // Create repositories directly with the provided modelContext
        let streakRepository = StreakRepository(modelContext: modelContext)
        let reflectionRepository = ReflectionRepository(modelContext: modelContext)
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
    }

    // Keep the original init for DIContainer if needed elsewhere
    init(
        getStreakStatsUseCase: GetStreakStatsUseCaseProtocol,
        calculateStreakUseCase: CalculateStreakUseCaseProtocol
    ) {
        self.getStreakStatsUseCase = getStreakStatsUseCase
        self.calculateStreakUseCase = calculateStreakUseCase
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
}
