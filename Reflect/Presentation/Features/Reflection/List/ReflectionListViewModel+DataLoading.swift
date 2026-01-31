import Foundation
import SwiftData
import Combine
import OSLog

// MARK: - Data Loading Extension

extension ReflectionListViewModel {
    @MainActor
    func loadReflections() async {
        let startTime = CFAbsoluteTimeGetCurrent()
        os_log("🚀 [PERF] loadReflections started", log: .default, type: .info)

        isLoading = true
        errorMessage = nil

        do {
            let searchStart = CFAbsoluteTimeGetCurrent()
            let filters = buildFilters()
            reflections = try await searchUseCase.execute(filters: filters)
            os_log("🔍 [PERF] Search completed (%d items) in %.3fms", log: .default, type: .info, reflections.count, (CFAbsoluteTimeGetCurrent() - searchStart) * 1000)

            let groupingStart = CFAbsoluteTimeGetCurrent()
            await groupReflectionsByDate()  // Now async
            os_log("📅 [PERF] Grouping completed in %.3fms", log: .default, type: .info, (CFAbsoluteTimeGetCurrent() - groupingStart) * 1000)

            isLoading = false
            os_log("✅ [PERF] loadReflections TOTAL took %.3fms", log: .default, type: .info, (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        } catch {
            isLoading = false
            os_log("⚠️ [PERF] loadReflections failed: %@", log: .default, type: .error, error.localizedDescription)
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
