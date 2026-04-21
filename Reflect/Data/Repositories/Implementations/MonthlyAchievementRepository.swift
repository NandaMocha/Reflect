import Foundation
import SwiftData

final class MonthlyAchievementRepository: MonthlyAchievementRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() async throws -> [MonthlyAchievement] {
        let descriptor = FetchDescriptor<MonthlyAchievement>(
            sortBy: [SortDescriptor(\.id, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetch(year: Int, month: Int) async throws -> MonthlyAchievement? {
        let id = String(format: "%04d-%02d", year, month)
        let descriptor = FetchDescriptor<MonthlyAchievement>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func getOrCreate(year: Int, month: Int) async throws -> MonthlyAchievement {
        if let existing = try await fetch(year: year, month: month) {
            return existing
        }

        let newAchievement = MonthlyAchievement(year: year, month: month)
        modelContext.insert(newAchievement)
        try modelContext.save()
        return newAchievement
    }

    func update(_ achievement: MonthlyAchievement) async throws {
        achievement.updatedAt = Date()
        try modelContext.save()
    }

    func getLastNMonths(_ n: Int) async throws -> [MonthlyAchievement] {
        var requiredMonthStrings: Set<String> = []
        var current = Calendar.current.startOfDay(for: .now)

        for _ in 0..<n {
            let year = Calendar.current.component(.year, from: current)
            let month = Calendar.current.component(.month, from: current)
            requiredMonthStrings.insert(String(format: "%04d-%02d", year, month))
            current = Calendar.current.date(byAdding: .month, value: -1, to: current) ?? current
        }

        let descriptor = FetchDescriptor<MonthlyAchievement>()
        let allAchievements = try modelContext.fetch(descriptor)

        return allAchievements.filter { requiredMonthStrings.contains($0.id) }
    }
}
