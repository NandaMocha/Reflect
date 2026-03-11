import Foundation
import SwiftData

final class BadgeRepository: BadgeRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() async throws -> [Badge] {
        let descriptor = FetchDescriptor<Badge>(sortBy: [SortDescriptor(\.name)])
        return try modelContext.fetch(descriptor)
    }

    func fetch(id: String) async throws -> Badge? {
        let descriptor = FetchDescriptor<Badge>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchUnlocked() async throws -> [Badge] {
        let descriptor = FetchDescriptor<Badge>(
            predicate: #Predicate { $0.isUnlocked == true },
            sortBy: [SortDescriptor(\.unlockedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func update(_ badge: Badge) async throws {
        badge.updatedAt = Date()
        try modelContext.save()
    }

    func unlock(_ badge: Badge) async throws {
        badge.unlock()
        try modelContext.save()
    }

    // MARK: - New Methods for Badge System v2

    /// Fetch permanent badges (achievements that are earned once and kept forever)
    func fetchPermanentBadges() async throws -> [Badge] {
        let allBadges = try await fetchAll()
        return allBadges.filter { $0.type == .permanent }
    }

    /// Fetch all newly unlocked badges (earned today)
    func fetchNewlyUnlockedBadges() async throws -> [Badge] {
        let allBadges = try await fetchUnlocked()
        let today = Calendar.current.startOfDay(for: Date())

        return allBadges.filter { badge in
            guard let unlockedAt = badge.unlockedAt else { return false }
            return Calendar.current.isDate(unlockedAt, inSameDayAs: today)
        }
    }

    /// Fetch badges by category
    func fetchBadges(in category: BadgeCategory) async throws -> [Badge] {
        let allBadges = try await fetchAll()
        return allBadges.filter { $0.category == category }
    }
}
