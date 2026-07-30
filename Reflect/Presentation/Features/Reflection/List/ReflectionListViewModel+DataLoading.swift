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
            await groupReflectionsByDate()
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
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
