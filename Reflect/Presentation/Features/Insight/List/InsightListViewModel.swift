import Foundation
import Observation

@Observable
@MainActor
final class InsightListViewModel {
    // MARK: - State

    var typeFilter: InsightType?
    var searchQuery: String = ""
    var errorMessage: String?

    // MARK: - Dependencies

    private let deleteUseCase: DeleteInsightUseCaseProtocol

    // MARK: - Initialization

    init(deleteUseCase: DeleteInsightUseCaseProtocol) {
        self.deleteUseCase = deleteUseCase
    }

    // MARK: - Actions

    func filteredAndGrouped(_ insights: [Insight]) -> [(group: InsightDateGroup, insights: [Insight])] {
        var filtered = insights

        if let typeFilter {
            filtered = filtered.filter { $0.type == typeFilter }
        }

        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            filtered = filtered.filter { $0.text.localizedCaseInsensitiveContains(trimmedQuery) }
        }

        var buckets: [InsightDateGroup: [Insight]] = [:]
        for insight in filtered {
            let group = InsightDateGroup.group(for: insight.createdAt)
            buckets[group, default: []].append(insight)
        }

        return buckets
            .map { group, insights in
                (group: group, insights: insights.sorted { $0.createdAt > $1.createdAt })
            }
            .sorted { $0.group < $1.group }
    }

    func delete(_ insight: Insight) async {
        do {
            try await deleteUseCase.execute(insight: insight)
            HapticManager.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }
}
