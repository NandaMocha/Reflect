import Foundation
import SwiftData

final class LearningRepository: LearningRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() async throws -> [Learning] {
        let descriptor = FetchDescriptor<Learning>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetch(id: UUID) async throws -> Learning? {
        let descriptor = FetchDescriptor<Learning>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func create(_ learning: Learning) async throws {
        let allLearnings = try await fetchAll()
        learning.sortOrder = allLearnings.count
        modelContext.insert(learning)
        try modelContext.save()
    }

    func update(_ learning: Learning) async throws {
        learning.updatedAt = Date()
        try modelContext.save()
    }

    func delete(_ learning: Learning) async throws {
        modelContext.delete(learning)
        try modelContext.save()
    }

    func reorder(_ learnings: [Learning]) async throws {
        for (index, learning) in learnings.enumerated() {
            learning.sortOrder = index
        }
        try modelContext.save()
    }
}
