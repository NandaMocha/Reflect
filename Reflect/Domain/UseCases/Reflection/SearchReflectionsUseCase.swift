import Foundation

protocol SearchReflectionsUseCaseProtocol {
    func execute(filters: SearchFilters) async throws -> [Reflection]
}

final class SearchReflectionsUseCase: SearchReflectionsUseCaseProtocol {
    private let repository: ReflectionRepositoryProtocol

    init(repository: ReflectionRepositoryProtocol) {
        self.repository = repository
    }

    func execute(filters: SearchFilters) async throws -> [Reflection] {
        var results: [Reflection]

        // Start with base query
        if !filters.query.isEmpty {
            results = try await repository.search(query: filters.query)
        } else if let learningId = filters.learningId {
            results = try await repository.fetchByLearning(learningId)
        } else if filters.favoritesOnly {
            results = try await repository.fetchFavorites()
        } else {
            results = try await repository.fetchAll()
        }

        // Apply hashtag filter
        if !filters.hashtags.isEmpty {
            results = results.filter { reflection in
                let reflectionHashtags = Set(reflection.hashtags.map { $0.name.lowercased() })
                let filterHashtags = Set(filters.hashtags.map { $0.lowercased() })
                return !reflectionHashtags.isDisjoint(with: filterHashtags)
            }
        }

        // Apply favorites filter (if not already applied)
        if filters.favoritesOnly && !filters.query.isEmpty {
            results = results.filter { $0.isFavorite }
        }

        // Apply date range filter
        if let dateRange = filters.dateRange {
            results = results.filter { reflection in
                reflection.createdAt >= dateRange.startDate &&
                reflection.createdAt <= dateRange.endDate
            }
        }

        // Apply sorting
        results = sort(results, by: filters.sortOption)

        return results
    }

    private func sort(_ reflections: [Reflection], by option: Constants.SortOption) -> [Reflection] {
        switch option {
        case .newestFirst:
            return reflections.sorted { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            return reflections.sorted { $0.createdAt < $1.createdAt }
        case .alphabeticalAZ:
            return reflections.sorted { $0.title.lowercased() < $1.title.lowercased() }
        case .alphabeticalZA:
            return reflections.sorted { $0.title.lowercased() > $1.title.lowercased() }
        case .recentlyUpdated:
            return reflections.sorted { $0.updatedAt > $1.updatedAt }
        }
    }
}
