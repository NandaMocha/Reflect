import Foundation
import SwiftData

final class HashtagRepository: HashtagRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() async throws -> [Hashtag] {
        let descriptor = FetchDescriptor<Hashtag>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetch(name: String) async throws -> Hashtag? {
        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespaces)
        let descriptor = FetchDescriptor<Hashtag>(
            predicate: #Predicate { $0.name == normalizedName }
        )
        return try modelContext.fetch(descriptor).first
    }

    func fetchOrCreate(name: String) async throws -> Hashtag {
        if let existing = try await fetch(name: name) {
            return existing
        }

        let newHashtag = Hashtag(name: name)
        modelContext.insert(newHashtag)
        try modelContext.save()
        return newHashtag
    }

    func fetchPopular(limit: Int) async throws -> [Hashtag] {
        let allHashtags = try await fetchAll()
        return Array(
            allHashtags
                .sorted { $0.usageCount > $1.usageCount }
                .prefix(limit)
        )
    }

    func search(query: String) async throws -> [Hashtag] {
        let lowercasedQuery = query.lowercased()
        let descriptor = FetchDescriptor<Hashtag>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        let allHashtags = try modelContext.fetch(descriptor)

        return allHashtags.filter { $0.name.contains(lowercasedQuery) }
    }

    func delete(_ hashtag: Hashtag) async throws {
        modelContext.delete(hashtag)
        try modelContext.save()
    }

    func cleanupUnused() async throws {
        let allHashtags = try await fetchAll()
        for hashtag in allHashtags where hashtag.reflections.isEmpty {
            modelContext.delete(hashtag)
        }
        try modelContext.save()
    }
}
