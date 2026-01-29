import Foundation

// MARK: - Filtering Extension

extension ReflectionListViewModel {
    func clearFilters() {
        showFavoritesOnly = false
        learningFilter = nil
        searchQuery = ""
        Task { @MainActor in
            await loadReflections()
        }
    }

    func setLearningFilter(_ learning: Learning?) {
        learningFilter = learning
        Task { @MainActor in
            await loadReflections()
        }
    }

    func toggleFavorites() {
        showFavoritesOnly.toggle()
        Task { @MainActor in
            await loadReflections()
        }
    }

    func updateSortOption(_ option: Constants.SortOption) {
        sortOption = option
        Task { @MainActor in
            await loadReflections()
        }
    }

    func buildFilters() -> SearchFilters {
        SearchFilters(
            query: searchQuery,
            learningId: learningFilter?.id,
            favoritesOnly: showFavoritesOnly,
            sortOption: sortOption
        )
    }
}
