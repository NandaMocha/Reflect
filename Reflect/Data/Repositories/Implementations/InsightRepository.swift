import Foundation
import SwiftData

final class InsightRepository: InsightRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() async throws -> [Insight] {
        let descriptor = FetchDescriptor<Insight>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetch(id: UUID) async throws -> Insight? {
        let descriptor = FetchDescriptor<Insight>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    func create(_ insight: Insight) async throws {
        modelContext.insert(insight)
        try modelContext.save()
    }

    func update(_ insight: Insight) async throws {
        insight.updatedAt = Date()
        try modelContext.save()
    }

    func delete(_ insight: Insight) async throws {
        modelContext.delete(insight)
        try modelContext.save()
    }
}
