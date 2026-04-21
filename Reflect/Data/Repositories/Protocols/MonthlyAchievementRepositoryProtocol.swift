import Foundation

protocol MonthlyAchievementRepositoryProtocol {
    func fetchAll() async throws -> [MonthlyAchievement]
    func fetch(year: Int, month: Int) async throws -> MonthlyAchievement?
    func getOrCreate(year: Int, month: Int) async throws -> MonthlyAchievement
    func update(_ achievement: MonthlyAchievement) async throws
    func getLastNMonths(_ n: Int) async throws -> [MonthlyAchievement]
}
