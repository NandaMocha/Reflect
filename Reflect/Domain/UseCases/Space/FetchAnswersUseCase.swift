import Foundation

protocol FetchAnswersUseCaseProtocol {
    func execute(for reflection: SpaceReflection, in space: Space) async throws -> [SpaceAnswer]
}

/// Passthrough to the repository's answer fetch (cloud fetch + cache reconcile).
@MainActor
final class FetchAnswersUseCase: FetchAnswersUseCaseProtocol {
    private let repository: SpaceRepositoryProtocol

    init(repository: SpaceRepositoryProtocol) {
        self.repository = repository
    }

    func execute(for reflection: SpaceReflection, in space: Space) async throws -> [SpaceAnswer] {
        try await repository.fetchAnswers(for: reflection, in: space)
    }
}
