import Foundation
import SwiftData
import Combine

// MARK: - Data Loading Extension

extension ReflectionListViewModel {
    @MainActor
    func loadReflections() async {
        isLoading = true
        errorMessage = nil

        do {
            let filters = buildFilters()
            reflections = try await searchUseCase.execute(filters: filters)
            groupReflectionsByDate()
            await loadPopularHashtags()
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func loadPopularHashtags() async {
        do {
            popularHashtags = try await hashtagRepository.fetchPopular(limit: 10)
        } catch {
            popularHashtags = []
        }
    }

    @MainActor
    func performSearch() async {
        await loadReflections()
    }

    func updateSearchQuery(_ query: String) {
        searchQuery = query
        searchSubject.send(query)
    }
}
