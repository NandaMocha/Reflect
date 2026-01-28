import Foundation

protocol FetchLearningsUseCaseProtocol {
    func execute() async throws -> [Learning]
    func execute(id: UUID) async throws -> Learning?
}

final class FetchLearningsUseCase: FetchLearningsUseCaseProtocol {
    private let repository: LearningRepositoryProtocol

    init(repository: LearningRepositoryProtocol) {
        self.repository = repository
    }

    func execute() async throws -> [Learning] {
        try await repository.fetchAll()
    }

    func execute(id: UUID) async throws -> Learning? {
        try await repository.fetch(id: id)
    }
}
