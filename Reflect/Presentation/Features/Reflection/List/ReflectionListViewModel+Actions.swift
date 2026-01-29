import Foundation
import SwiftData

// MARK: - Actions Extension

extension ReflectionListViewModel {
    @MainActor
    func deleteReflection(_ reflection: Reflection) async {
        do {
            try await deleteUseCase.execute(reflection: reflection)
            reflections.removeAll { $0.id == reflection.id }
            groupReflectionsByDate()
            HapticManager.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }

    @MainActor
    func toggleFavorite(_ reflection: Reflection) async {
        reflection.isFavorite.toggle()
        reflection.updatedAt = Date()
        try? modelContext.save()
        HapticManager.shared.selection()
    }

    var hasActiveFilters: Bool {
        showFavoritesOnly || learningFilter != nil || !searchQuery.isEmpty
    }

    var isEmpty: Bool {
        reflections.isEmpty && !isLoading
    }

    var emptyStateMessage: String {
        if hasActiveFilters {
            return "No reflections match your filters"
        }
        return "Start your journey by creating your first reflection"
    }
}
