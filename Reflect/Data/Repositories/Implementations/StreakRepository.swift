import Foundation
import SwiftData

final class StreakRepository: StreakRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func getStreakData() async throws -> StreakData {
        let descriptor = FetchDescriptor<StreakData>()
        let streakDataList = try modelContext.fetch(descriptor)

        if let existing = streakDataList.first {
            return existing
        }

        // Create initial streak data if none exists
        let newStreakData = StreakData()
        modelContext.insert(newStreakData)
        try modelContext.save()
        return newStreakData
    }

    func updateStreakData(_ streakData: StreakData) async throws {
        streakData.updatedAt = Date()
        try modelContext.save()
    }

    func getCurrentStreak() async throws -> Int {
        let streakData = try await getStreakData()
        return streakData.currentStreak
    }

    func getLongestStreak() async throws -> Int {
        let streakData = try await getStreakData()
        return streakData.longestStreak
    }
}
