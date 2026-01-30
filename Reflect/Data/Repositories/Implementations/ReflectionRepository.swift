import Foundation
import SwiftData

final class ReflectionRepository: ReflectionRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() async throws -> [Reflection] {
        let descriptor = FetchDescriptor<Reflection>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetch(id: UUID) async throws -> Reflection? {
        let descriptor = FetchDescriptor<Reflection>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchByLearning(_ learningId: UUID) async throws -> [Reflection] {
        let descriptor = FetchDescriptor<Reflection>(
            predicate: #Predicate { $0.learning?.id == learningId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchFavorites() async throws -> [Reflection] {
        let descriptor = FetchDescriptor<Reflection>(
            predicate: #Predicate { $0.isFavorite == true },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func search(query: String) async throws -> [Reflection] {
        // Use SwiftData predicate for server-side filtering instead of in-memory filtering
        // This significantly improves performance for large datasets
        let lowercasedQuery = query.lowercased()

        let descriptor = FetchDescriptor<Reflection>(
            predicate: #Predicate<Reflection> { reflection in
                reflection.title.contains(lowercasedQuery) ||
                reflection.plainTextContent.contains(lowercasedQuery)
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        return try modelContext.fetch(descriptor)
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
