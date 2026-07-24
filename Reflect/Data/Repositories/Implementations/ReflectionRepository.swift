import Foundation
import SwiftData

final class ReflectionRepository: ReflectionRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll(limit: Int? = nil, offset: Int? = nil) async throws -> [Reflection] {
        var descriptor = FetchDescriptor<Reflection>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        applyPagination(to: &descriptor, limit: limit, offset: offset)
        return try modelContext.fetch(descriptor)
    }

    func fetch(id: UUID) async throws -> Reflection? {
        let descriptor = FetchDescriptor<Reflection>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchByLearning(_ learningId: UUID, limit: Int? = nil, offset: Int? = nil) async throws -> [Reflection] {
        var descriptor = FetchDescriptor<Reflection>(
            predicate: #Predicate { $0.learning?.id == learningId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        applyPagination(to: &descriptor, limit: limit, offset: offset)
        return try modelContext.fetch(descriptor)
    }

    func fetchFavorites(limit: Int? = nil, offset: Int? = nil) async throws -> [Reflection] {
        var descriptor = FetchDescriptor<Reflection>(
            predicate: #Predicate { $0.isFavorite == true },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        applyPagination(to: &descriptor, limit: limit, offset: offset)
        return try modelContext.fetch(descriptor)
    }

    func search(query: String, limit: Int? = nil, offset: Int? = nil) async throws -> [Reflection] {
        // Store-side, case- and diacritic-insensitive match. (Previously lowercased the
        // query but compared against original-case text, so "Titanic" was unfindable.)
        let query = query

        var descriptor = FetchDescriptor<Reflection>(
            predicate: #Predicate<Reflection> { reflection in
                reflection.title.localizedStandardContains(query) ||
                reflection.plainTextContent.localizedStandardContains(query)
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        applyPagination(to: &descriptor, limit: limit, offset: offset)
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Private Helper

    private func applyPagination<T>(to descriptor: inout FetchDescriptor<T>, limit: Int?, offset: Int?) {
        if let limit = limit {
            descriptor.fetchLimit = limit
        }
        if let offset = offset {
            descriptor.fetchOffset = offset
        }
    }

    func create(_ reflection: Reflection) async throws {
        modelContext.insert(reflection)
        // Enqueue the sync op into the SAME context BEFORE saving, so the one save() commits
        // the reflection and its outbox entry atomically. A reflection upsert carries its
        // current attachments, so this hook also covers image/voice/video add & remove.
        await enqueueUpsert(id: reflection.id)
        try modelContext.save()
    }

    func update(_ reflection: Reflection) async throws {
        reflection.updatedAt = Date()
        await enqueueUpsert(id: reflection.id)
        try modelContext.save()
    }

    func delete(_ reflection: Reflection) async throws {
        // Capture the id before deletion — the outbox op must outlive the row.
        let id = reflection.id
        modelContext.delete(reflection)
        await enqueueDelete(id: id)
        try modelContext.save()
    }

    func toggleFavorite(_ reflection: Reflection) async throws {
        reflection.isFavorite.toggle()
        reflection.updatedAt = Date()
        await enqueueUpsert(id: reflection.id)
        try modelContext.save()
    }

    // MARK: - Auto-sync enqueue

    /// Inserts an upsert/delete outbox op via the shared coordinator (which shares this
    /// repository's ModelContext). No-op when auto-sync is disabled or paused.
    private func enqueueUpsert(id: UUID) async {
        await DIContainer.shared.makeSyncCoordinator().enqueueUpsert(.reflection, id: id)
    }

    private func enqueueDelete(id: UUID) async {
        await DIContainer.shared.makeSyncCoordinator().enqueueDelete(.reflection, id: id)
    }

    // MARK: - Convenience Methods without pagination

    func fetchAll() async throws -> [Reflection] {
        try await fetchAll(limit: nil, offset: nil)
    }

    func fetchByLearning(_ learningId: UUID) async throws -> [Reflection] {
        try await fetchByLearning(learningId, limit: nil, offset: nil)
    }

    func fetchFavorites() async throws -> [Reflection] {
        try await fetchFavorites(limit: nil, offset: nil)
    }
}
