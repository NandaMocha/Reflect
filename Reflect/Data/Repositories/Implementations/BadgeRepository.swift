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
}
