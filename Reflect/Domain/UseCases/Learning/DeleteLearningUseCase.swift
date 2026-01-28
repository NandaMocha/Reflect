import Foundation

protocol DeleteLearningUseCaseProtocol {
    func execute(learning: Learning) async throws
}

final class DeleteLearningUseCase: DeleteLearningUseCaseProtocol {
    private let repository: LearningRepositoryProtocol

    init(repository: LearningRepositoryProtocol) {
        self.repository = repository
    }

    func execute(learning: Learning) async throws {
        try await repository.delete(learning)
    }
}
