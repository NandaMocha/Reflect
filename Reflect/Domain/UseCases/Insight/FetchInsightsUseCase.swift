import Foundation

protocol FetchInsightsUseCaseProtocol {
    func execute() async throws -> [Insight]
    func execute(type: InsightType) async throws -> [Insight]
}

final class FetchInsightsUseCase: FetchInsightsUseCaseProtocol {
    private let repository: InsightRepositoryProtocol

    init(repository: InsightRepositoryProtocol) {
        self.repository = repository
    }

    func execute() async throws -> [Insight] {
        try await repository.fetchAll()
    }

    func execute(type: InsightType) async throws -> [Insight] {
        try await repository.fetchAll().filter { $0.type == type }
    }
}
