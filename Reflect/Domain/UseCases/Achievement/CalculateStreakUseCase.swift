import Foundation

protocol CalculateStreakUseCaseProtocol {
    func execute() async throws -> Int
}

final class CalculateStreakUseCase: CalculateStreakUseCaseProtocol {
    private let streakRepository: StreakRepositoryProtocol
    private let reflectionRepository: ReflectionRepositoryProtocol
    private let calculationService: StreakCalculationService

    init(
        streakRepository: StreakRepositoryProtocol,
        reflectionRepository: ReflectionRepositoryProtocol,
        calculationService: StreakCalculationService
    ) {
        self.streakRepository = streakRepository
        self.reflectionRepository = reflectionRepository
        self.calculationService = calculationService
    }

    func execute() async throws -> Int {
        let reflections = try await reflectionRepository.fetchAll()
        let newStreak = calculationService.calculateCurrentStreak(reflections: reflections)

        let streakData = try await streakRepository.getStreakData()
        let previousStreak = streakData.currentStreak

        streakData.currentStreak = newStreak
        streakData.lastSubmissionDate = Date()

        if newStreak > streakData.longestStreak {
            streakData.longestStreak = newStreak
        }

        if newStreak > 0 && previousStreak == 0 {
            streakData.streakStartDate = Date()
        }

        try await streakRepository.updateStreakData(streakData)

        return newStreak
    }
}
