import Foundation

protocol StreakRepositoryProtocol {
    func getStreakData() async throws -> StreakData
    func updateStreakData(_ streakData: StreakData) async throws
    func getCurrentStreak() async throws -> Int
    func getLongestStreak() async throws -> Int
}
