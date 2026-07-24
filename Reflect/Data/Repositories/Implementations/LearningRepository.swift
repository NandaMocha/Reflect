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
        await enqueueUpsert(id: learning.id)
        try modelContext.save()
    }

    func update(_ learning: Learning) async throws {
        learning.updatedAt = Date()
        await enqueueUpsert(id: learning.id)
        try modelContext.save()
    }

    func delete(_ learning: Learning) async throws {
        // The learning's reflections are nullified (deleteRule .nullify), not deleted. Capture
        // their ids first and re-upsert them so their cloud record's learningID is cleared,
        // rather than left pointing at a now-deleted learning.
        let learningID = learning.id
        let affectedReflectionIDs = learning.reflections.map(\.id)

        modelContext.delete(learning)

        let coordinator = await DIContainer.shared.makeSyncCoordinator()
        await coordinator.enqueueDelete(.learning, id: learningID)
        for reflectionID in affectedReflectionIDs {
            await coordinator.enqueueUpsert(.reflection, id: reflectionID)
        }

        try modelContext.save()
    }

    func reorder(_ learnings: [Learning]) async throws {
        let coordinator = await DIContainer.shared.makeSyncCoordinator()
        for (index, learning) in learnings.enumerated() {
            learning.sortOrder = index
            await coordinator.enqueueUpsert(.learning, id: learning.id)
        }
        try modelContext.save()
    }

    // MARK: - Auto-sync enqueue

    /// Inserts an upsert outbox op via the shared coordinator (which shares this repository's
    /// ModelContext). No-op when auto-sync is disabled or paused.
    private func enqueueUpsert(id: UUID) async {
        await DIContainer.shared.makeSyncCoordinator().enqueueUpsert(.learning, id: id)
    }
}
