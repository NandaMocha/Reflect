import Foundation

// MARK: - Filtering Extension

extension ReflectionListViewModel {
    func toggleHashtag(_ hashtag: String) {
        if selectedHashtags.contains(hashtag) {
            selectedHashtags.remove(hashtag)
        } else {
            selectedHashtags.insert(hashtag)
        }
        HapticManager.shared.selection()
        Task { @MainActor in
            await loadReflections()
        }
    }

    func clearFilters() {
        selectedHashtags.removeAll()
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
            hashtags: Array(selectedHashtags),
            favoritesOnly: showFavoritesOnly,
            sortOption: sortOption
        )
    }
}
