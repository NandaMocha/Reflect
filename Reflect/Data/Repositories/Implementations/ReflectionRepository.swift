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
        // Use SwiftData predicate for server-side filtering instead of in-memory filtering
        // This significantly improves performance for large datasets
        let lowercasedQuery = query.lowercased()

        var descriptor = FetchDescriptor<Reflection>(
            predicate: #Predicate<Reflection> { reflection in
                reflection.title.contains(lowercasedQuery) ||
                reflection.plainTextContent.contains(lowercasedQuery)
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
        try modelContext.save()
    }

    func update(_ reflection: Reflection) async throws {
        reflection.updatedAt = Date()
        try modelContext.save()
    }

    func delete(_ reflection: Reflection) async throws {
        modelContext.delete(reflection)
        try modelContext.save()
    }

    func toggleFavorite(_ reflection: Reflection) async throws {
        reflection.isFavorite.toggle()
        reflection.updatedAt = Date()
        try modelContext.save()
    }
}
