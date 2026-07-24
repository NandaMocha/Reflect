import Foundation

protocol DeleteInsightUseCaseProtocol {
    func execute(insight: Insight) async throws
}

final class DeleteInsightUseCase: DeleteInsightUseCaseProtocol {
    private let repository: InsightRepositoryProtocol

    init(repository: InsightRepositoryProtocol) {
        self.repository = repository
    }

    func execute(insight: Insight) async throws {
        try await repository.delete(insight)
    }
}
